import Foundation
import UserNotifications
import Observation

/// Gli avvisi prima dell'all aboard.
///
/// Notifiche locali a **istanti fissi**, non recinti geografici. Un recinto avrebbe
/// richiesto il permesso di posizione permanente e il monitoraggio in background:
/// più invadente da chiedere, più difficile da giustificare in revisione, e più
/// fragile — un recinto non scatta se il GPS non aggancia, mentre un orario scatta
/// sempre. L'ora dell'all aboard la sappiamo già: basta quella.
///
/// Restano al livello di interruzione normale. Il livello "time sensitive", che
/// supererebbe Non disturbare, richiede una capability da abilitare sull'App ID e
/// non è disponibile con un profilo di sviluppo personale — quindi l'app non lo
/// dichiara affatto, invece di chiederlo e vederselo negare in fase di firma.
///
/// Conseguenza da tenere presente: con un Full Immersion attivo l'avviso **non**
/// suona. Per quel caso la difesa è la Live Activity sulla schermata di blocco, che
/// resta visibile senza dipendere dalle notifiche.
@MainActor
@Observable
final class NotificationScheduler {

    /// Con quanto anticipo avvisare, in minuti. Il secondo avviso è il richiamo finale.
    static let leadOptions = [30, 45, 60, 90, 120]
    static let finalCallMinutes = 20

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    var leadMinutes: Int = 60 {
        didSet { UserDefaults.standard.set(leadMinutes, forKey: Keys.lead) }
    }
    var isEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    private enum Keys {
        static let lead = "cruisy.notify.leadMinutes"
        static let enabled = "cruisy.notify.enabled"
    }

    private let centre = UNUserNotificationCenter.current()

    init() {
        if let stored = UserDefaults.standard.object(forKey: Keys.lead) as? Int,
           Self.leadOptions.contains(stored) {
            leadMinutes = stored
        }
        if UserDefaults.standard.object(forKey: Keys.enabled) != nil {
            isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        }
    }

    var isAuthorised: Bool {
        authorization == .authorized || authorization == .provisional
    }

    func refreshAuthorization() async {
        authorization = await centre.notificationSettings().authorizationStatus
    }

    /// Chiede il permesso. Va chiesto quando l'utente attiva l'avviso, non all'avvio:
    /// a quel punto il motivo è evidente e la risposta è informata.
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await centre.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    /// Riprogramma tutti gli avvisi della crociera.
    ///
    /// Cancella e riscrive invece di aggiornare: gli orari cambiano (un annuncio di
    /// bordo, un ritardo) e riconciliare a mano lascerebbe in giro avvisi vecchi che
    /// suonerebbero all'ora sbagliata. Meglio poche decine di notifiche riscritte da
    /// zero che una superstite che mente.
    func reschedule(for voyage: Voyage?) async {
        centre.removeAllPendingNotificationRequests()

        guard isEnabled, isAuthorised, let voyage else { return }

        let now = Date()
        for call in voyage.calls {
            guard let allAboard = call.allAboard, allAboard > now else { continue }

            await add(for: call, allAboard: allAboard, clock: voyage.clock,
                      minutesBefore: leadMinutes, isFinalCall: false)
            if leadMinutes > Self.finalCallMinutes {
                await add(for: call, allAboard: allAboard, clock: voyage.clock,
                          minutesBefore: Self.finalCallMinutes, isFinalCall: true)
            }
        }
    }

    private func add(for call: PortCall, allAboard: Date, clock: ShipClock,
                     minutesBefore: Int, isFinalCall: Bool) async {
        let fireDate = allAboard.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = isFinalCall
            ? String(localized: "Ultima chiamata: \(minutesBefore) minuti")
            : String(localized: "Rientro a bordo fra \(minutesBefore) minuti")
        content.body = String(localized: "All aboard alle \(clock.time(allAboard)), ora di bordo, a \(call.name).")
        content.sound = .default
        content.threadIdentifier = call.id.uuidString

        // Un trigger a intervallo e non a componenti di calendario: l'istante è già
        // assoluto, e passarlo per un calendario significherebbe rifare la conversione
        // di fuso una seconda volta, con una seconda occasione di sbagliarla.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false)

        let request = UNNotificationRequest(
            identifier: "allAboard.\(call.id.uuidString).\(minutesBefore)",
            content: content, trigger: trigger)

        try? await centre.add(request)
    }

    func cancelAll() {
        centre.removeAllPendingNotificationRequests()
    }

    /// Quanti avvisi sono davvero in coda: serve a mostrare lo stato vero invece
    /// di uno stato locale che potrebbe non corrispondere.
    func pendingCount() async -> Int {
        await centre.pendingNotificationRequests().count
    }
}
