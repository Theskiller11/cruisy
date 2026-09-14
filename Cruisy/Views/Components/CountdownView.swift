import SwiftUI

/// Il numero grande.
///
/// Rende un `Countdown`, cioè due istanti, non un contatore. `TimelineView` chiede
/// a SwiftUI di ridisegnare **solo questa vista** ogni secondo: la schermata attorno
/// resta ferma. Le cifre non sono animate di proposito — a 1 Hz un'animazione
/// produce sfarfallio invece di fluidità.
struct CountdownView: View {
    let countdown: Countdown
    var size: CGFloat = 52
    var cap: CGFloat = 76
    var colour: Color = Palette.inkPrimary
    /// Scarto fra l'ora vera e il punto di osservazione: zero in produzione.
    var offset: TimeInterval = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let instant = context.date.addingTimeInterval(offset)
            Text(countdown.formatted(at: instant))
                .displayNumeral(size: size, cap: cap)
                .foregroundStyle(colour)
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

/// L'unità sotto il countdown, che spiega che cosa sono quelle cifre.
///
/// Prende l'istante da chi la usa invece di leggersi l'ora da sola: prima teneva un
/// `now` catturato alla comparsa e senza lo scarto di osservazione, quindi accanto a
/// un countdown di dieci ore scriveva "m · s".
struct CountdownUnits: View {
    let countdown: Countdown
    let now: Date

    var body: some View {
        Text(countdown.components(at: now).hours > 0 ? "h · m · s" : "m · s")
            .font(Type.metricLabel)
            .foregroundStyle(Palette.inkTertiary)
            .accessibilityHidden(true)
    }
}
