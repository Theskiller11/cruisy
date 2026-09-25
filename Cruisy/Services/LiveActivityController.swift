import Foundation
import ActivityKit
import Observation

/// Avvia, aggiorna e chiude la Live Activity dell'all aboard.
///
/// Lo stato acceso/spento **non** è una variabile di questa classe: si legge da
/// `Activity.activities`, cioè dal sistema. Una Live Activity la si può chiudere dalla
/// schermata di blocco, senza passare dall'app: un interruttore appoggiato su uno
/// stato locale prima o poi mostrerebbe "attiva" mentre non c'è più niente.
@MainActor
@Observable
final class LiveActivityController {

    /// In porto l'attività si accende nelle ultime tre ore prima del rientro a bordo.
    ///
    /// Erano otto, il massimo che il sistema concede a una Live Activity: ma otto
    /// ore di countdown fisso sulla schermata di blocco, dal caffè della mattina,
    /// sono ingombro, e Matteo l'ha trovata accesa a quattro ore dall'all aboard
    /// senza che servisse a niente. Nelle ultime tre si comincia a pensare al
    /// rientro: lì serve. Una sosta dura comunque più di così, quindi la si arma
    /// quando il traguardo entra nella finestra, non all'attracco.
    static let portLead: TimeInterval = 3 * 3600

    /// In navigazione l'attività si accende solo nell'ultima ora e mezza prima
    /// dell'attracco.
    ///
    /// Prima non serve a niente: una traversata dura mezza giornata e un countdown
    /// fisso sulla schermata di blocco per dodici ore è solo ingombro. Nell'ultima
    /// ora e mezza invece si comincia a guardare fuori, e lì diventa utile.
    static let seaLead: TimeInterval = 90 * 60

    /// L'ultima ora prima del traguardo: da qui l'attività passa in allarme.
    /// È l'unica transizione automatica che il sistema concede, via `staleDate`.
    static let urgentLead: TimeInterval = 3600

    private(set) var activityID: String?
    private(set) var lastError: String?

    var isRunning: Bool { current != nil }

    private var current: Activity<AllAboardAttributes>? {
        Activity<AllAboardAttributes>.activities.first
    }

    var areActivitiesAllowed: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Vero quando manca ancora troppo perché valga la pena accenderla.
    func isTooEarly(for countdown: Countdown, at now: Date, atSea: Bool = false) -> Bool {
        countdown.remaining(at: now) > (atSea ? Self.seaLead : Self.portLead)
    }

    func refresh() {
        activityID = current?.id
    }

    /// Accende la Live Activity per lo scalo in corso.
    @discardableResult
    func start(voyage: Voyage, call: PortCall, countdown: Countdown, at now: Date,
               kind: AllAboardAttributes.Kind = .allAboard, milesRemaining: Double? = nil) -> Bool {
        guard areActivitiesAllowed, current == nil else { return false }
        guard !isTooEarly(for: countdown, at: now, atSea: kind.isAtSea) else { return false }

        let attributes = AllAboardAttributes(
            portName: call.name,
            shipName: voyage.shipName,
            allAboardLabel: voyage.clock.time(countdown.target),
            berthLabel: call.berth.name ?? call.berth.label)

        let state = AllAboardAttributes.ContentState(
            start: countdown.start, target: countdown.target, origin: countdown.origin,
            kind: kind, milesRemaining: milesRemaining)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                // `staleDate` a un'ora dal traguardo: è l'unico momento in cui il
                // sistema ci lascia cambiare aspetto da soli, e lo si spende per far
                // scattare l'allarme rosso invece che per segnalare un dato vecchio.
                content: .init(state: state,
                               staleDate: max(now, countdown.target.addingTimeInterval(-Self.urgentLead))),
                pushType: nil)
            activityID = activity.id
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Riallinea l'attività quando gli orari cambiano — un annuncio di bordo, una
    /// correzione. Senza questo, la Live Activity conterebbe verso l'orario vecchio.
    func update(countdown: Countdown, kind: AllAboardAttributes.Kind = .allAboard,
                milesRemaining: Double? = nil) async {
        // Letta qui e non da `current`: un valore preso da una proprietà dell'attore
        // resta legato all'attore, e `Activity.update` — che gira fuori — non lo
        // accetterebbe. Un valore locale appena letto dal sistema è libero.
        guard let activity = Activity<AllAboardAttributes>.activities.first else { return }
        let state = AllAboardAttributes.ContentState(
            start: countdown.start, target: countdown.target, origin: countdown.origin,
            kind: kind, milesRemaining: milesRemaining)
        await activity.update(.init(state: state,
                                    staleDate: countdown.target.addingTimeInterval(-Self.urgentLead)))
    }

    /// Riallinea l'attività a quello che l'app sta contando adesso, e la chiude
    /// quando non c'è più niente da contare.
    ///
    /// Esiste perché **nessuno la chiude da solo**: ActivityKit la lascia sullo
    /// schermo di blocco e nella Dynamic Island finché non la si termina. Senza
    /// questo, passato l'all aboard resta lì con il conto fermo a zero — e un
    /// countdown morto che non se ne va è peggio che non averlo mai acceso.
    ///
    /// Si occupa anche del caso opposto: se gli orari sono stati corretti dopo un
    /// annuncio di bordo, l'attività conterebbe verso l'orario vecchio.
    func reconcile(focus: Voyage.Focus?, at now: Date, milesRemaining: Double? = nil) async {
        guard let activity = current else { return }

        // Niente più da contare, o il traguardo è passato.
        guard let focus, now < focus.countdown.target else {
            await end()
            return
        }

        // Cambiato porto: l'attività punta a un traguardo che non è più quello.
        guard activity.attributes.portName == focus.port.name else {
            await end()
            return
        }

        // Il traguardo si è spostato più in là della finestra — un ritardo
        // annunciato, una correzione — e l'attività conterebbe ore che non le
        // spettano. Si chiude: quando la finestra si riapre, `RootTabView` la
        // riaccende da sé. Prima la si aggiornava e basta, e restava accesa a
        // quattro ore dal traguardo, fuori dalla finestra che le spetta.
        if isTooEarly(for: focus.countdown, at: now, atSea: activity.content.state.kind.isAtSea) {
            await end()
            return
        }

        // Stesso porto, orario corretto: si riallinea invece di chiudere.
        if activity.content.state.target != focus.countdown.target {
            await update(countdown: focus.countdown,
                         kind: activity.content.state.kind,
                         milesRemaining: milesRemaining)
        }
    }

    func end() async {
        for activity in Activity<AllAboardAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activityID = nil
    }
}
