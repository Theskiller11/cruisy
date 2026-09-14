import SwiftUI

/// Che mare c'è, e che tempo fa.
///
/// La riga più importante non è l'altezza dell'onda: è il nome che le si dà. "Molto
/// mosso" dice a chiunque quello che "2,1 m" dice solo a chi naviga. I metri restano,
/// più piccoli, per chi li vuole.
///
/// L'età del dato è sempre in vista. In mezzo all'oceano la rete non c'è, e una
/// previsione di ieri va benissimo purché sia dichiarata come tale.
struct SeaStateCard: View {
    let conditions: MarineConditions
    let now: Date
    /// Il titolo cambia con dove sei: in mare è il mare intorno alla nave, in porto
    /// è il tempo che troverai a terra.
    var title: String = String(localized: "Mare")
    /// Dove si è, per decidere la riga sotto il nome del mare: vedi `SeaState.note`.
    var mooring: SeaState.Mooring = .underway
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveHStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                Text(title).eyebrow()
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                freshness
            }

            headline

            if !metrics.isEmpty {
                Divider().overlay(Palette.hairline)
                MetricRow(metrics: metrics)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 24, prominence: .card)
    }

    // MARK: La riga grande

    @ViewBuilder
    private var headline: some View {
        // Ai corpi accessibili la riga diventa colonna: glifo, stato del mare e
        // temperatura affiancati non ci starebbero, e stringere le colonne fa
        // sbordare la pagina invece di tenerla insieme.
        AdaptiveHStack(verticalAlignment: .center, spacing: 12) {
            if let code = conditions.weatherCode {
                Image(systemName: WeatherCode.glyph(code))
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.inkPrimary)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let sea = conditions.seaState {
                    Text(sea.label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(sea.isRough ? Palette.ashore : Palette.inkPrimary)
                    if let note = sea.note(mooring) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(mooring == .tender && sea.rawValue >= SeaState.moltoMosso.rawValue
                                             ? Palette.ashore : Palette.inkSecondary)
                    }
                } else if let code = conditions.weatherCode {
                    Text(WeatherCode.label(code))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.inkPrimary)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if let air = conditions.airTemperature {
                Text(Format.temperature(air))
                    // Derivata da uno stile di testo, non da un numero di punti:
                    // così cresce col Dynamic Type invece di restare piccola in
                    // mezzo a etichette diventate enormi.
                    .font(.system(.title, design: .rounded, weight: .light))
                    .foregroundStyle(Palette.inkPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var metrics: [Metric] {
        var list: [Metric] = []
        if let wave = conditions.waveHeight {
            list.append(Metric(value: Format.metres(wave), label: String(localized: "Onda"),
                               spoken: String(localized: "Onda \(Format.metres(wave))")))
        }
        if let wind = conditions.windSpeed {
            let direction = conditions.windDirection.map { Geo.compassPoint($0) } ?? ""
            list.append(Metric(value: "\(Int(wind)) kn \(direction)".trimmingCharacters(in: .whitespaces),
                               label: String(localized: "Vento")))
        }
        if let sea = conditions.seaTemperature {
            list.append(Metric(value: Format.temperature(sea), label: String(localized: "Acqua")))
        }
        return list
    }

    // MARK: L'età del dato

    @ViewBuilder
    private var freshness: some View {
        let stale = conditions.isStale(at: now)
        Label {
            Text(stale ? String(localized: "di \(Format.duration(conditions.age(at: now))) fa")
                       : String(localized: "aggiornato"))
        } icon: {
            Image(systemName: stale ? "clock.badge.exclamationmark" : "checkmark.circle")
        }
        .font(.caption2)
        .foregroundStyle(stale ? Palette.ashore : Palette.inkTertiary)
        .labelStyle(.titleAndIcon)
    }
}
