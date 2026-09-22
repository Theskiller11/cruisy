import SwiftUI

/// Le miglia percorse, messe in scala con qualcosa che si può immaginare.
///
/// «1.216 miglia nautiche» è un numero senza appigli. Qui diventa **una frazione di
/// traversata atlantica**, con la barra che dice quanto manca al traguardo dopo.
///
/// I paragoni si scelgono da soli, e questa è la parte che conta: mostrarli tutti e
/// sette darebbe «68 volte il Canale della Manica» accanto a «0,00005 volte il giro
/// del mondo», che sono due modi diversi di non dire niente. Restano solo quelli in
/// cui il numero è leggibile a occhio.
struct DistanceScaleCard: View {
    @Environment(\.livery) private var livery
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
        Ticket {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Miglia percorse").ticketEyebrow(livery.signalInk)
                    Spacer(minLength: 8)
                    yearPicker
                }
                Text(Format.nauticalMiles(miles))
                    .ticketNumeral(size: 58, cap: 84)
                    .foregroundStyle(livery.ink)
                totals
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)
        } stub: {
            VStack(alignment: .leading, spacing: 14) {
                if miles > 0 {
                    milestoneBar
                    if !comparisons.isEmpty { comparisonRows }
                } else {
                    Text("Le miglia si contano da sole mentre navighi.")
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.field)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
    }

    /// I tre conteggi, in una riga: giorni di mare, porti, crociere.
    private var totals: some View {
        Text([
            logbook.seaDays == 1 ? String(localized: "1 giorno di mare") : String(localized: "\(logbook.seaDays) giorni di mare"),
            logbook.stamps.count == 1 ? String(localized: "1 porto") : String(localized: "\(logbook.stamps.count) porti"),
            logbook.voyages.count == 1 ? String(localized: "1 crociera") : String(localized: "\(logbook.voyages.count) crociere"),
        ].joined(separator: " · "))
            .font(TicketType.place)
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(livery.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
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
                HStack(spacing: 4) {
                    Text(year.map(String.init) ?? String(localized: "Tutto"))
                        .ticketFieldLabel(livery.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(livery.field)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(livery.rule, lineWidth: 1))
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
                    Capsule().fill(livery.rule)
                    Capsule()
                        .fill(livery.signal)
                        .frame(width: max(6, geometry.size.width * progress))
                }
            }
            .frame(height: 8)

            if let next {
                let remaining = next.nauticalMiles - miles
                // Ai corpi accessibili il nome va a capo sulle parole, non sulle
                // lettere: il moltiplicatore scende sotto invece di stringerlo.
                AdaptiveHStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Ai corpi accessibili il glifo se ne va: è decorativo, e la
                        // larghezza che ruba faceva spezzare «Mediterraneo» col
                        // trattino. Un nome tagliato a metà si legge peggio di un
                        // nome senza icona.
                        if !typeSize.isAccessibilitySize {
                            Image(systemName: next.glyph)
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(livery.signalInk)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.name)
                                .font(TicketType.rowTitle)
                                .foregroundStyle(livery.ink)
                            Text("mancano \(Format.nauticalMiles(remaining))")
                                .font(TicketType.rowDetail)
                                .foregroundStyle(livery.field)
                        }
                    }
                    AdaptiveSpacer(minLength: 0)
                    Text(Format.multiplier(next.times(miles)))
                        .font(TicketType.fieldValue)
                        .foregroundStyle(livery.signalInk)
                }
            } else {
                Text("Hai superato tutti i traguardi. Complimenti sinceri.")
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.ink)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: I paragoni

    private var comparisonRows: some View {
        VStack(spacing: 0) {
            TicketRule().padding(.bottom, 2)
            ForEach(comparisons) { milestone in
                AdaptiveHStack(verticalAlignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if !typeSize.isAccessibilitySize {
                            Image(systemName: milestone.glyph)
                                .font(.system(.caption2, weight: .semibold))
                                .foregroundStyle(livery.field)
                                .frame(width: 16)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(milestone.name)
                                .font(TicketType.rowDetail)
                                .foregroundStyle(livery.ink)
                            if typeSize.isAccessibilitySize {
                                Text(milestone.detail)
                                    .font(.caption2)
                                    .foregroundStyle(livery.field)
                            }
                        }
                    }
                    AdaptiveSpacer(minLength: 8)
                    Text(Format.multiplier(milestone.times(miles)))
                        .font(TicketType.fieldValue)
                        .foregroundStyle(livery.ink)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(milestone.name), \(Format.multiplier(milestone.times(miles)))"))
            }
        }
    }
}
