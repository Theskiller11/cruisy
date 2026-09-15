import SwiftUI

/// Che mare c'è, in pastiglie sullo scafo: «Mosso · 0,8 m», «28°», «Vento 10 kn E».
///
/// La riga più importante non è l'altezza dell'onda: è il nome che le si dà. «Molto
/// mosso» dice a chiunque quello che «2,1 m» dice solo a chi naviga. I metri restano
/// accanto, per chi li vuole. E l'età del dato è sempre in vista: in mezzo
/// all'oceano la rete non c'è, e una previsione di ieri va benissimo purché sia
/// dichiarata come tale.
struct WeatherChips: View {
    @Environment(\.livery) private var livery
    let conditions: MarineConditions
    let now: Date
    /// Dove si è, per decidere la nota sotto le pastiglie: vedi `SeaState.note`.
    var mooring: SeaState.Mooring = .underway

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowRow(spacing: 8) {
                if let sea = conditions.seaState, let wave = conditions.waveHeight {
                    HullChip("\(sea.label) · \(Format.metres(wave))", glyph: "water.waves")
                } else if let code = conditions.weatherCode {
                    HullChip(WeatherCode.label(code), glyph: WeatherCode.glyph(code))
                }
                if let air = conditions.airTemperature {
                    HullChip(Format.temperature(air), glyph: conditions.weatherCode.map { WeatherCode.glyph($0) })
                }
                if let wind = conditions.windSpeed {
                    let direction = conditions.windDirection.map { Geo.compassPoint($0) } ?? ""
                    HullChip("\(Int(wind)) kn \(direction)".trimmingCharacters(in: .whitespaces), glyph: "wind")
                }
                if let sea = conditions.seaTemperature {
                    HullChip(String(localized: "Acqua \(Format.temperature(sea))"), glyph: "thermometer.medium")
                }
            }
            HStack(spacing: 6) {
                if let note = conditions.seaState?.note(mooring) {
                    Text(note)
                }
                if conditions.isStale(at: now) {
                    Text("· \(String(localized: "di \(Format.duration(conditions.age(at: now))) fa"))")
                }
            }
            .font(.caption)
            .foregroundStyle(livery.onHullMuted)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
