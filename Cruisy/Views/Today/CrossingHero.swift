import SwiftUI

/// Il pannello del giorno di mare: quanto manca all'arrivo.
///
/// Qui il progresso è una **linea**, non un anello. Una sosta in porto è un ciclo
/// chiuso — si arriva e si riparte dallo stesso punto — mentre una traversata va da
/// un posto a un altro: la forma deve somigliare a ciò che rappresenta, altrimenti
/// serve una didascalia per rimediare.
struct CrossingHero: View {
    let from: PortCall
    let to: PortCall
    let countdown: Countdown
    let clock: ShipClock
    let now: Date
    var offset: TimeInterval = 0
    let fix: ShipFix?
    let speedUnit: SpeedUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AdaptiveHStack {
                Label {
                    Text("In navigazione")
                        .font(Type.metricLabel.weight(.semibold))
                } icon: {
                    Image(systemName: "water.waves")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Palette.underway)
                AdaptiveSpacer()
                ProvenanceChip(origin: countdown.origin,
                               freshness: fix.map { $0.freshness(at: now) })
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("All'arrivo a \(to.name)")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.inkSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CountdownView(countdown: countdown, size: 52, cap: 76, offset: offset)
                    CountdownUnits(countdown: countdown, now: now)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("All'arrivo a \(to.name)"))

                // Nessuna rivendicazione di puntualità: senza un dato in tempo reale
                // dalla nave, un bollino "in orario" sarebbe un'affermazione che l'app
                // non può sostenere. Si dice l'orario e da dove viene, e basta.
                Text("previsto \(Format.dayMonth(to.arrival, clock: clock)) · \(clock.time(to.arrival))")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, 6)
            }

            CrossingProgress(from: from, to: to, countdown: countdown, now: now)

            Divider().overlay(Palette.hairline)

            MetricRow(metrics: metrics)
        }
        .padding(18)
        .glassSurface(cornerRadius: 30, prominence: .card, tint: Palette.underway)
    }

    /// Velocità media di tratta, ricavata dagli orari: distanza fra i due porti
    /// diviso il tempo previsto.
    private var scheduledSpeed: Double? {
        let hours = to.arrival.timeIntervalSince(from.castOff) / 3600
        guard hours > 0 else { return nil }
        return Geo.nauticalMiles(from: from.coordinate, to: to.coordinate) / hours
    }

    /// Le grandezze da mostrare, ognuna col nome di ciò che è davvero.
    ///
    /// Quando il GPS è fermo non dà né velocità né rotta. Invece di inventarle
    /// spacciando una media di tratta per una lettura istantanea, si cambia
    /// l'etichetta: "velocità media" e "rilevamento" sono altre grandezze, e dirle
    /// col loro nome costa una parola e salva l'onestà del dato.
    private var metrics: [Metric] {
        var metrics: [Metric] = []

        if let speed = fix?.speed, speed > 0.2 {
            metrics.append(Metric(value: Format.speed(knots: speed, unit: speedUnit),
                                  label: String(localized: "Velocità")))
        } else if let average = scheduledSpeed {
            metrics.append(Metric(value: Format.speed(knots: average, unit: speedUnit),
                                  label: String(localized: "Velocità media")))
        }

        if let course = fix?.course {
            metrics.append(Metric(value: Format.bearing(course),
                                  label: String(localized: "Rotta"),
                                  spoken: Format.course(course)))
        } else if let fix {
            let bearing = Geo.bearing(from: fix.coordinate, to: to.coordinate)
            metrics.append(Metric(value: Format.bearing(bearing),
                                  label: String(localized: "Rilevamento"),
                                  spoken: Format.course(bearing)))
        }

        if let fix {
            let miles = Geo.nauticalMiles(from: fix.coordinate, to: to.coordinate)
            metrics.append(Metric(value: Format.nauticalMiles(miles),
                                  label: String(localized: "Alla meta"),
                                  spoken: String(localized: "\(Int(miles)) miglia nautiche")))
        }
        return metrics
    }
}

/// La barra che va da un porto all'altro, con i nomi alle estremità.
///
/// Non una barra dritta ma **un'onda che scorre**: la traversata è la cosa che sta
/// succedendo mentre guardi, e una barra ferma non lo dice. Il moto è lento e
/// piccolo di proposito — deve leggersi come mare, non come un caricamento.
private struct CrossingProgress: View {
    let from: PortCall
    let to: PortCall
    let countdown: Countdown
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double { countdown.progress(at: now) }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if reduceMotion {
                    // Chi ha chiesto meno movimento riceve la stessa forma, ferma:
                    // l'onda resta, l'oscillazione no.
                    wave(phase: 0)
                } else {
                    TimelineView(.animation) { context in
                        wave(phase: context.date.timeIntervalSinceReferenceDate * 1.1)
                    }
                }
            }
            .frame(height: 12)

            HStack {
                Text(from.name)
                    .font(Type.metricLabel)
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 12)
                Text(to.name)
                    .font(Type.metricLabel)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Traversata da \(from.name) a \(to.name)"))
        .accessibilityValue(Text("\(Int(progress * 100)) per cento"))
    }

    /// Traccia e parte percorsa disegnate **dalla stessa fase**.
    ///
    /// Prima erano due onde separate — quella colorata animata, quella dietro ferma a
    /// zero — e così combaciavano solo quando la fase capitava a giro intero. Nel
    /// resto del tempo la cresta di una cadeva sul cavo dell'altra, e la parte
    /// percorsa sembrava uscire dalla traccia. Una sola forma, mascherata: non
    /// possono più separarsi.
    @ViewBuilder
    private func wave(phase: Double) -> some View {
        let shape = WaveShape(phase: phase, amplitude: 2.2)
        ZStack(alignment: .leading) {
            shape.fill(Palette.ink.opacity(0.14))
            shape.fill(Palette.underway)
                .mask(alignment: .leading) { filled }
        }
    }

    /// La maschera che taglia l'onda alla quota percorsa.
    private var filled: some View {
        GeometryReader { geometry in
            Rectangle()
                .frame(width: max(6, geometry.size.width * progress))
                .fluid(Motion.settle, value: progress)
        }
    }
}

/// Un'onda sinusoidale spessa, che scorre col tempo.
private struct WaveShape: Shape {
    var phase: Double
    var amplitude: CGFloat
    /// Quanto è lunga una cresta, in punti.
    var wavelength: CGFloat = 34

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let thickness = min(rect.height * 0.42, 5)
        let step: CGFloat = 2

        func y(_ x: CGFloat) -> CGFloat {
            midY + sin(Double(x) / Double(wavelength) * 2 * .pi + phase) * Double(amplitude)
        }

        // Bordo superiore da sinistra a destra…
        path.move(to: CGPoint(x: rect.minX, y: y(rect.minX) - thickness / 2))
        var x = rect.minX
        while x <= rect.maxX {
            path.addLine(to: CGPoint(x: x, y: y(x) - thickness / 2))
            x += step
        }
        // …e quello inferiore al ritorno, così resta una striscia di spessore
        // costante invece di una linea.
        x = rect.maxX
        while x >= rect.minX {
            path.addLine(to: CGPoint(x: x, y: y(x) + thickness / 2))
            x -= step
        }
        path.closeSubpath()
        return path
    }
}
