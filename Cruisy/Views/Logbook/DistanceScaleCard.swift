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
                if miles > 0 {
                    milestoneBar.padding(.top, 8)
                    if let line = comparisonLine {
                        Text(line)
                            .font(TicketType.rowDetail)
                            .foregroundStyle(livery.field)
                            .padding(.top, 10)
                    }
                } else {
                    Text("Le miglia si contano da sole mentre navighi.")
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.field)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 16)
        } stub: {
            // I tre conteggi nella matrice del biglietto: prima erano una riga di
            // maiuscole sotto il numero, e si leggevano come un sottotitolo.
            TicketMatrix(fields: [
                TicketField(label: String(localized: "Porti"), value: "\(logbook.stamps.count)"),
                TicketField(label: String(localized: "Giorni di mare"), value: "\(logbook.seaDays)"),
                TicketField(label: String(localized: "Crociere"), value: "\(logbook.voyages.count)"),
            ], columns: 3)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
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

    // MARK: Il righello

    /// Il prossimo traguardo, e una riga che va dall'ultimo superato a lui con la
    /// nave dove sei arrivato.
    ///
    /// Solo due nomi, ai capi: con tutti i traguardi sulla riga le etichette si
    /// accavallavano già all'italiano a corpo normale, figurarsi al tedesco a corpo
    /// grande. Gli altri paragoni stanno in una riga di testo sotto.
    @ViewBuilder
    private var milestoneBar: some View {
        if let next {
            VStack(alignment: .leading, spacing: 8) {
                AdaptiveHStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !typeSize.isAccessibilitySize {
                            Image(systemName: next.glyph)
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(livery.signalInk)
                        }
                        Text(next.name)
                            .font(TicketType.rowTitle)
                            .foregroundStyle(livery.ink)
                    }
                    AdaptiveSpacer(minLength: 0)
                    Text("mancano \(Format.nauticalMiles(next.nauticalMiles - miles))")
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.field)
                }
                ruler
                HStack(alignment: .firstTextBaseline) {
                    Text(passed?.name ?? String(localized: "Imbarco"))
                    Spacer(minLength: 8)
                    Text(Format.multiplier(next.times(miles)))
                        .foregroundStyle(livery.signalInk)
                }
                .font(TicketType.fieldLabel)
                .foregroundStyle(livery.field)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(next.name): mancano \(Format.nauticalMiles(next.nauticalMiles - miles))"))
        } else {
            Text("Hai superato tutti i traguardi. Complimenti sinceri.")
                .font(TicketType.rowDetail)
                .foregroundStyle(livery.ink)
        }
    }

    private var ruler: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = min(max(width * progress, 10), width - 10)
            ZStack(alignment: .leading) {
                Capsule().fill(livery.rule).frame(height: 6)
                Capsule().fill(livery.signal).frame(width: x, height: 6)
                Circle().fill(livery.ink).frame(width: 9, height: 9)
                Circle().fill(livery.paper)
                    .overlay(Circle().stroke(livery.ink, lineWidth: 2))
                    .frame(width: 10, height: 10)
                    .offset(x: width - 10)
                Image(systemName: "ferry.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(livery.signal)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(livery.paper))
                    .overlay(Circle().stroke(livery.signal, lineWidth: 2))
                    .offset(x: x - 11)
            }
            .frame(height: 22)
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    /// «15× Il Canale di Panama · 36× Il Canale della Manica»: gli altri traguardi
    /// già superati, in una riga sola invece che in una lista. L'ultimo superato e
    /// il prossimo stanno già ai capi del righello, e ripeterli qui sembrava un errore.
    private var comparisonLine: String? {
        let shown = comparisons.filter { $0.times(miles) >= 1 && $0 != passed }.suffix(2)
        guard !shown.isEmpty else { return nil }
        return shown.reversed().map { "\(Format.multiplier($0.times(miles))) \($0.name)" }
            .joined(separator: " · ")
    }
}
