import SwiftUI

/// Le miglia percorse, messe in scala con qualcosa che si può immaginare.
///
/// «1.216 miglia nautiche» è un numero senza appigli. Il diario lo mostrava e basta,
/// e non diceva niente a nessuno. Qui diventa **una frazione di traversata
/// atlantica**, con la barra che dice quanto manca al traguardo dopo.
///
/// I paragoni si scelgono da soli, e questa è la parte che conta: mostrarli tutti e
/// sette darebbe «68 volte il Canale della Manica» accanto a «0,00005 volte il giro
/// del mondo», che sono due modi diversi di non dire niente. Restano solo quelli in
/// cui il numero è leggibile a occhio.
struct DistanceScaleCard: View {
    let logbook: Logbook
    /// L'anno mostrato, o nullo per tutto.
    @Binding var year: Int?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var miles: Double { logbook.nauticalMiles(inYear: year) }
    private var passed: Milestone? { Milestone.scale.passed(miles) }
    private var next: Milestone? { Milestone.scale.next(after: miles) }
    private var comparisons: [Milestone] { Milestone.scale.meaningful(for: miles, excluding: next) }

    /// A che punto si sta fra il traguardo superato e il prossimo.
    ///
    /// In scala **logaritmica**, perché i traguardi crescono per moltiplicazione:
    /// fra 3.100 e 25.000 miglia in scala lineare si starebbe incollati a sinistra
    /// per anni, e la barra non si muoverebbe mai.
    private var progress: Double {
        guard let next else { return 1 }
        let floor = passed?.nauticalMiles ?? 1
        guard miles > floor, next.nauticalMiles > floor else { return 0 }
        return log(miles / floor) / log(next.nauticalMiles / floor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if miles > 0 {
                milestoneBar
                if !comparisons.isEmpty { comparisonRows }
            } else {
                Text("Le miglia si contano da sole mentre navighi.")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassSurface(cornerRadius: 26, prominence: .card)
    }

    // MARK: Il numero e l'interruttore

    private var header: some View {
        AdaptiveHStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.nauticalMiles(miles))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("Miglia percorse").eyebrow()
            }
            Spacer(minLength: 0)
            yearPicker
        }
    }

    /// Anno per anno, o tutto.
    ///
    /// Compare **solo se c'è più di un anno**: un menu con una voce sola è una
    /// promessa che non mantiene niente.
    @ViewBuilder
    private var yearPicker: some View {
        let years = logbook.years()
        if years.count > 1 {
            Menu {
                Button("Tutto") { year = nil }
                ForEach(years, id: \.self) { anno in
                    Button(String(anno)) { year = anno }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(year.map(String.init) ?? String(localized: "Tutto"))
                        .font(Type.metricLabel.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Palette.inkPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .glassCapsule(prominence: .chip)
            }
            .accessibilityLabel(Text("Periodo mostrato"))
        }
    }

    // MARK: La barra del traguardo

    @ViewBuilder
    private var milestoneBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.inkPrimary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.underway, Palette.action],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geometry.size.width * progress))
                }
            }
            .frame(height: 10)

            if let next {
                let remaining = next.nauticalMiles - miles
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: next.glyph)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.action)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.name)
                            .font(Type.rowTitle)
                            .foregroundStyle(Palette.inkPrimary)
                        Text("mancano \(Format.nauticalMiles(remaining))")
                            .font(Type.rowDetail)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(Format.multiplier(next.times(miles)))
                        .font(Type.metricValue)
                        .monospacedDigit()
                        .foregroundStyle(Palette.action)
                }
            } else {
                Text("Hai superato tutti i traguardi. Complimenti sinceri.")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.underway)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: I paragoni

    private var comparisonRows: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.hairline).padding(.bottom, 2)
            ForEach(comparisons) { milestone in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: milestone.glyph)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(milestone.name)
                            .font(Type.rowDetail)
                            .foregroundStyle(Palette.inkSecondary)
                        if typeSize.isAccessibilitySize {
                            Text(milestone.detail)
                                .font(.caption2)
                                .foregroundStyle(Palette.inkTertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Format.multiplier(milestone.times(miles)))
                        .font(Type.rowDetail.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkPrimary)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(milestone.name), \(Format.multiplier(milestone.times(miles)))"))
            }
        }
    }
}
