import SwiftUI

/// Le cifre che scorrono: «2:59:52».
///
/// Rende un `Countdown`, cioè due istanti, non un contatore. `TimelineView` chiede
/// a SwiftUI di ridisegnare **solo questa vista** ogni secondo: la schermata attorno
/// resta ferma. Le cifre non sono animate di proposito — a 1 Hz un'animazione
/// produce sfarfallio invece di fluidità.
///
/// Sul biglietto è la conseguenza dell'ora stampata, non il titolo: si ricorda
/// un'ora, non dei secondi. Per questo sta nella matrice, stretta e nera ma più
/// piccola dell'ora.
struct CountdownView: View {
    @Environment(\.livery) private var livery
    let countdown: Countdown
    var font: Font = TicketType.count
    var colour: Color?
    /// Scarto fra l'ora vera e il punto di osservazione: zero in produzione.
    var offset: TimeInterval = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let instant = context.date.addingTimeInterval(offset)
            // Sempre con le ore: «0:19:55», mai «19:55», che accanto a un'ora
            // stampata si leggerebbe come un orario.
            Text(countdown.formatted(at: instant, alwaysHours: true))
                .font(font)
                .foregroundStyle(colour ?? livery.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.identity)
                .accessibilityLabel(spokenLabel(at: instant))
        }
    }

    /// VoiceOver non deve sentire i secondi: cambierebbero a ogni ridisegno e
    /// renderebbero la schermata inascoltabile. Si legge al minuto.
    private func spokenLabel(at now: Date) -> String {
        let c = countdown.components(at: now)
        if c.hours > 0 {
            return String(localized: "\(c.hours) ore e \(c.minutes) minuti",
                          comment: "Countdown letto da VoiceOver")
        }
        if c.minutes > 0 {
            return String(localized: "\(c.minutes) minuti", comment: "Countdown letto da VoiceOver")
        }
        return String(localized: "meno di un minuto", comment: "Countdown letto da VoiceOver")
    }
}
