import SwiftUI

/// Una grandezza con la sua etichetta: 18,4 kt · VELOCITÀ.
struct Metric: Identifiable, Hashable {
    var id: String { label }
    var value: String
    var label: String
    /// Come lo legge VoiceOver, quando la forma abbreviata non basterebbe.
    var spoken: String?
}

/// La riga di metriche sotto il countdown.
///
/// Ai corpi di testo accessibili si reimpagina in verticale invece di stringere le
/// colonne. È la lezione già pagata altrove: scalare le **larghezze** fisse fa
/// sbordare la pagina, mentre cambiare impaginazione la tiene insieme. Si scalano
/// le altezze, non le larghezze.
struct MetricRow: View {
    let metrics: [Metric]
    /// Quante colonne per riga. Con `nil` resta tutto su una riga sola, com'era.
    ///
    /// Serve dove le grandezze sono più di tre — la scheda della nave — perché
    /// senza, l'ultima riga con un valore solo si allargava per tutta la larghezza
    /// e non stava più in colonna con quelle sopra.
    var columns: Int? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(metrics) { metric in
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.label)
                            .eyebrow()
                        Spacer(minLength: 12)
                        Text(metric.value)
                            .font(Type.metricValue)
                            .foregroundStyle(Palette.inkPrimary)
                            // Ai corpi accessibili "248.663 GT" andava a capo fra
                            // le cifre — "248.66" sopra e "3 GT" sotto. Un numero
                            // spezzato non è più un numero.
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("\(metric.label): \(metric.spoken ?? metric.value)"))
                }
            }
        } else if let columns, metrics.count > columns {
            VStack(spacing: 14) {
                ForEach(Array(stride(from: 0, to: metrics.count, by: columns)), id: \.self) { start in
                    let slice = Array(metrics[start..<min(start + columns, metrics.count)])
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(slice) { cell($0) }
                        // Le celle che mancano restano vuote ma tengono la colonna:
                        // se no l'ultimo valore si allarga e va fuori squadro con
                        // quelli della riga sopra.
                        ForEach(slice.count..<columns, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(metrics) { cell($0) }
            }
        }
    }

    @ViewBuilder
    private func cell(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.value)
                .font(Type.metricValue)
                .foregroundStyle(Palette.inkPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(metric.label)
                .eyebrow()
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(metric.label): \(metric.spoken ?? metric.value)"))
    }
}

/// Un riquadro con una sola grandezza in evidenza: ora di bordo, mare e vento.
struct MetricTile: View {
    let label: String
    let value: String
    var detail: String?
    var spoken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).eyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Text(detail)
                        .font(Type.rowDetail)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 20, prominence: .chip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(spoken ?? value)\(detail.map { ", \($0)" } ?? "")"))
    }
}

/// Il riquadro della posizione: latitudine e longitudine su due righe.
///
/// Su una riga sola non ci stanno nella metà di uno schermo, e venivano troncate a
/// "19°48'N · 70…" — cioè si perdeva proprio la longitudine. Impilate ci stanno, e
/// l'etichetta porta la provenienza, che è l'altra metà dell'informazione: una
/// posizione senza il suo grado di fiducia non dice abbastanza.
struct CoordinateTile: View {
    let fix: ShipFix
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: fix.origin.isMeasured ? "location.fill" : "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 9, weight: .semibold))
                Text(fix.origin.label)
                    .font(Type.eyebrow)
                    .tracking(Type.eyebrowTracking)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(fix.origin.isMeasured ? Palette.inkTertiary : Palette.ashore)

            VStack(alignment: .leading, spacing: 1) {
                Text(Format.latitude(fix.coordinate))
                Text(Format.longitude(fix.coordinate))
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(Palette.inkPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 20, prominence: .chip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Posizione, \(fix.origin.label)"))
        .accessibilityValue(Text(Format.coordinate(fix.coordinate)))
    }
}
