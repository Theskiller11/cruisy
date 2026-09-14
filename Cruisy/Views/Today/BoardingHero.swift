import SwiftUI

/// Il pannello prima dell'imbarco.
///
/// A crociera lontana un countdown in ore non è un'informazione: "1567:06:29" nessuno
/// lo legge come "sessantacinque giorni". Finché manca più di un giorno si conta in
/// **giorni**, che è l'unità in cui si pensa a una vacanza che deve ancora arrivare;
/// nelle ultime ore si passa alle cifre precise, perché lì il minuto torna a contare.
struct BoardingHero: View {
    let call: PortCall
    let countdown: Countdown
    let clock: ShipClock
    let now: Date
    var offset: TimeInterval = 0

    /// Sotto questa soglia si passa al countdown preciso.
    private static let precisionThreshold: TimeInterval = 36 * 3600

    private var isFarAway: Bool { countdown.remaining(at: now) > Self.precisionThreshold }

    /// Giorni di bordo che restano: la differenza fra le due mezzanotti, non le ore
    /// divise per 24. È così che una persona li conta.
    private var daysAway: Int {
        // Ogni mezzanotte col **suo** scarto: fra oggi e l'imbarco l'orologio di
        // bordo può essersi spostato. Poi si arrotonda, perché un'ora di scarto non
        // deve poter aggiungere o togliere un giorno all'attesa.
        let today = clock.startOfDay(for: now)
        let boarding = clock.startOfDay(for: countdown.target)
        return max(0, Int((boarding.timeIntervalSince(today) / 86_400).rounded()))
    }

    /// Vero quando il documento non diceva l'ora d'imbarco e questa è finita a
    /// mezzanotte: meglio tacere l'orario che mostrarne uno inventato.
    private var hasBoardingTime: Bool {
        let calendar = clock.calendar(at: countdown.target)
        return calendar.component(.hour, from: countdown.target) != 0
            || calendar.component(.minute, from: countdown.target) != 0
    }

    private var whenLine: String {
        let date = Format.dayMonth(countdown.target, clock: clock)
        return hasBoardingTime ? "\(date) · \(clock.time(countdown.target))" : date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AdaptiveHStack {
                Label {
                    Text("Imbarco").font(Type.metricLabel.weight(.semibold))
                } icon: {
                    Image(systemName: "suitcase.rolling.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Palette.action)
                AdaptiveSpacer()
                ProvenanceChip(origin: countdown.origin)
            }

            if isFarAway { countdownInDays } else { countdownInHours }

            Text("\(call.name) · \(whenLine)")
                .font(Type.rowDetail)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(18)
        .glassSurface(cornerRadius: 30, prominence: .card, tint: Palette.action)
    }

    // MARK: I due modi di contare

    private var countdownInDays: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(daysAway)")
                    .displayNumeral(size: 64, cap: 88)
                    .foregroundStyle(Palette.inkPrimary)
                Text(daysAway == 1 ? "giorno" : "giorni")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(daysAway == 1 ? "Manca un giorno all'imbarco"
                                     : "Mancano \(daysAway) giorni all'imbarco"))

            Text(encouragement)
                .font(Type.rowTitle)
                .foregroundStyle(Palette.action)
                .padding(.top, 4)
        }
    }

    private var countdownInHours: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CountdownView(countdown: countdown, size: 48, cap: 70, offset: offset)
                CountdownUnits(countdown: countdown, now: now)
            }
            Text("Ci siamo. Documenti, passaporto, valigia.")
                .font(Type.rowTitle)
                .foregroundStyle(Palette.action)
                .padding(.top, 6)
        }
    }

    /// Il tono cambia con l'avvicinarsi della partenza: da "manca ancora" a
    /// "preparati". Una sola riga, che è quanto serve — non è un'app di motivazione.
    private var encouragement: String {
        switch daysAway {
        case 0, 1: String(localized: "Preparati all'imbarco.")
        case 2...6: String(localized: "Ci siamo quasi: prepara la valigia.")
        case 7...29: String(localized: "Preparati a salpare.")
        default: String(localized: "Buona attesa. Goditela già da adesso.")
        }
    }
}
