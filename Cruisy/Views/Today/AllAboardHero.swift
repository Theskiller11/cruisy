import SwiftUI

/// Il pannello del giorno in porto: quanto manca al rientro obbligatorio.
///
/// Il countdown sta **dentro** l'anello, non accanto. Nel brief l'anello mostrava una
/// percentuale di sosta mentre il numero contava verso l'all aboard: due misure diverse
/// affiancate, più una percentuale che ridiceva col cerchio quello che il numero già
/// diceva con le cifre. Annidandoli, il legame non ha più bisogno di essere spiegato:
/// l'anello è il tempo che resta, e il tempo che resta è scritto al centro.
struct AllAboardHero: View {
    let call: PortCall
    let countdown: Countdown
    let clock: ShipClock
    let now: Date
    var offset: TimeInterval = 0

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 214

    /// L'anello si allarga col Dynamic Type ma non oltre: è un'altezza, quindi può
    /// crescere, ma deve restare dentro la larghezza dello schermo.
    private var diameter: CGFloat { min(ringSize, 300) }

    var body: some View {
        VStack(spacing: 16) {
            AdaptiveHStack {
                Text(call.name)
                    .eyebrow(Palette.ashore)
                    .lineLimit(2)
                AdaptiveSpacer()
                ProvenanceChip(origin: countdown.origin)
            }

            ProgressRing(countdown: countdown, now: now, lineWidth: 10, tint: Palette.ashore) {
                VStack(spacing: 4) {
                    Text("Rientro a bordo")
                        .eyebrow()
                    CountdownView(countdown: countdown, size: 44, cap: 58, colour: Palette.inkPrimary, offset: offset)
                    Text("entro le \(clock.time(countdown.target))")
                        .font(Type.rowDetail)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, 18)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityLabel(Text("Rientro a bordo a \(call.name) entro le \(clock.time(countdown.target))"))
            .accessibilityValue(Text(spokenRemaining))

            Divider().overlay(Palette.hairline)

            MetricRow(metrics: schedule)
        }
        .padding(18)
        .glassSurface(cornerRadius: 30, prominence: .card, tint: Palette.ashore)
    }

    private var spokenRemaining: String {
        let c = countdown.components(at: now)
        return c.hours > 0
            ? String(localized: "mancano \(c.hours) ore e \(c.minutes) minuti", comment: "Tempo residuo")
            : String(localized: "mancano \(c.minutes) minuti", comment: "Tempo residuo")
    }

    private var schedule: [Metric] {
        var metrics: [Metric] = [
            Metric(value: clock.time(call.arrival), label: String(localized: "Attracco"))
        ]
        if let departure = call.departure {
            metrics.append(Metric(value: clock.time(departure), label: String(localized: "Partenza")))
        }
        metrics.append(Metric(value: Format.duration(call.duration),
                              label: String(localized: "Sosta"),
                              spoken: Format.duration(call.duration)))
        return metrics
    }
}
