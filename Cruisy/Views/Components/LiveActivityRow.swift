import SwiftUI

/// L'interruttore della Live Activity.
///
/// Legge lo stato dal sistema a ogni comparsa, perché l'utente può averla chiusa
/// dalla schermata di blocco mentre l'app era in secondo piano.
struct LiveActivityRow: View {
    let voyage: Voyage
    let call: PortCall
    let countdown: Countdown
    let now: Date
    var kind: AllAboardAttributes.Kind = .allAboard
    var milesRemaining: Double?

    @Environment(LiveActivityController.self) private var activities

    var body: some View {
        if activities.areActivitiesAllowed {
            content
                .onAppear { activities.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if activities.isTooEarly(for: countdown, at: now, atSea: kind.isAtSea) {
            // Dire perché non si può, invece di mostrare un interruttore che non
            // farebbe nulla: un comando che non risponde è peggio di un comando assente.
            InfoRow(glyph: "clock.badge.xmark", tint: Palette.inkTertiary,
                    title: String(localized: "Countdown sulla schermata di blocco"),
                    subtitle: kind.isAtSea
                        ? String(localized: "Si accende nell'ultima ora e mezza prima dell'attracco.")
                        : String(localized: "Si potrà attivare nelle ultime otto ore prima dell'all aboard."))
        } else {
            Toggle(isOn: Binding(
                get: { activities.isRunning },
                set: { wanted in
                    if wanted {
                        activities.start(voyage: voyage, call: call, countdown: countdown,
                                         at: now, kind: kind, milesRemaining: milesRemaining)
                    } else {
                        Task { await activities.end() }
                    }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Countdown sulla schermata di blocco")
                            .font(Type.rowTitle)
                            .foregroundStyle(Palette.inkPrimary)
                        Text(activities.isRunning
                             ? String(localized: "Attivo · anche nella Dynamic Island")
                             // Vale la pena dirlo qui: senza il livello "time sensitive"
                             // una notifica non passa il Full Immersion, mentre questa
                             // resta visibile comunque.
                             : String(localized: "Resta visibile anche con Full Immersion attivo"))
                            .font(Type.rowDetail)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .tint(kind.isAtSea ? Palette.underway : Palette.ashore)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .glassSurface(cornerRadius: 20, prominence: .chip)
        }
    }
}


/// L'interruttore della Live Activity, dovunque serva mostrarlo.
///
/// Si ricava da sé porto e countdown dallo stato dell'app. Prima quella logica
/// stava nella schermata Oggi: portarla anche nelle Impostazioni avrebbe voluto
/// dire copiarla, e due copie della stessa condizione divergono sempre.
struct LiveActivitySetting: View {
    @Environment(VoyageStore.self) private var store
    @Environment(PositionService.self) private var position

    var body: some View {
        if let voyage = store.voyage, let moment = store.moment, let focus = store.focus {
            riga(voyage: voyage, moment: moment, focus: focus)
        } else {
            // Senza crociera non c'è niente da contare: si dice, invece di mostrare
            // un interruttore che non farebbe nulla.
            InfoRow(glyph: "clock.badge.xmark", tint: Palette.inkTertiary,
                    title: String(localized: "Countdown sulla schermata di blocco"),
                    subtitle: String(localized: "Si accenderà quando avrai una crociera in corso."))
        }
    }

    @ViewBuilder
    private func riga(voyage: Voyage, moment: Voyage.Moment, focus: Voyage.Focus) -> some View {
        if case .inPort(let call) = moment, case .allAboard = focus.kind {
            LiveActivityRow(voyage: voyage, call: call,
                            countdown: focus.countdown, now: store.now)
        } else if case .atSea(_, let to) = moment {
            let fix = position.shipFix(for: voyage, at: store.now)
            LiveActivityRow(voyage: voyage, call: to,
                            countdown: focus.countdown, now: store.now,
                            kind: .arrival,
                            milesRemaining: fix.map {
                                Geo.nauticalMiles(from: $0.coordinate, to: to.coordinate) })
        } else {
            InfoRow(glyph: "clock.badge.xmark", tint: Palette.inkTertiary,
                    title: String(localized: "Countdown sulla schermata di blocco"),
                    subtitle: String(localized: "Si accende in porto prima dell'all aboard, e in mare prima dell'attracco."))
        }
    }
}
