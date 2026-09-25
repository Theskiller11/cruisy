import SwiftUI

/// La pagina di una crociera del diario: la carta con la rotta, il biglietto, i
/// giorni uno per uno, i primati.
///
/// È qui, e solo qui, che resta la linea percorsa quando si sbarca: il Diario
/// mostra i totali, ogni crociera la sua strada. La crociera in corso ha la stessa
/// pagina, con la linea fin dove si è arrivati.
struct LoggedVoyageScreen: View {
    let entryID: UUID

    @Environment(VoyageStore.self) private var store
    @Environment(\.livery) private var livery
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false
    @State private var confirmingTrackRemoval = false
    /// Il nome in alto compare quando il biglietto col nome è passato sotto la barra.
    @State private var showsTitle = false

    private var entry: LoggedVoyage? { store.logbook.logbook.voyages.first { $0.id == entryID } }

    /// La crociera in corso non ha ancora la rotta nel diario — ci entra alla
    /// chiusura — quindi la si prende dal registratore.
    private var isCurrent: Bool { entryID == store.voyage?.id && store.moment != .completed }

    private var track: Track? {
        if isCurrent { return store.recorder.track.isEmpty ? nil : store.recorder.track }
        return entry?.track
    }

    private static let chartHeight: CGFloat = 320

    var body: some View {
        ZStack {
            livery.hull.ignoresSafeArea()
            if let entry {
                content(entry)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let entry, showsTitle {
                    VStack(spacing: 0) {
                        Text(entry.shipName).font(TicketType.place).textCase(.uppercase)
                            .foregroundStyle(livery.onHull)
                        if let start = entry.start, let end = entry.end {
                            Text(Format.dateRange(from: start, to: end, clock: entry.clock))
                                .font(.caption2).foregroundStyle(livery.onHullMuted)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsTitle)
        .confirmationDialog("Togliere questa crociera dal diario?", isPresented: $confirmingRemoval,
                            titleVisibility: .visible) {
            Button("Togli dal diario", role: .destructive) {
                if let entry { store.logbook.forget(entry) }
                dismiss()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Le miglia e i porti di questa crociera spariranno dai totali.")
        }
        .confirmationDialog("Togliere la rotta di questa crociera?", isPresented: $confirmingTrackRemoval,
                            titleVisibility: .visible) {
            Button("Togli la rotta", role: .destructive) {
                if let entry { store.logbook.forgetTrack(of: entry) }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Miglia, porti e timbri restano. Sparisce la linea di dove sei passato.")
        }
    }

    private func content(_ entry: LoggedVoyage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LoggedVoyageChart(entry: entry, track: track, topInset: 90)
                    .frame(height: Self.chartHeight)
                    .overlay(alignment: .bottomTrailing) { legend.padding(12).padding(.bottom, 40) }
                    .padding(.horizontal, -16)
                    .padding(.bottom, -52)

                LoggedVoyageTicket(entry: entry, track: track, isCurrent: isCurrent)
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY < 40 } action: {
                        showsTitle = $0
                    }

                Text("Giorno per giorno").ticketEyebrow(livery.onHullMuted)
                    .padding(.horizontal, 4).padding(.top, 8)
                LoggedDays(entry: entry, track: track,
                           through: isCurrent ? store.now : nil, isCurrent: isCurrent)

                let tiles = records(entry)
                if !tiles.isEmpty {
                    Text("Primati di questa crociera").ticketEyebrow(livery.onHullMuted)
                        .padding(.horizontal, 4).padding(.top, 8)
                    RecordTiles(tiles: tiles)
                }

                if !isCurrent { actions(entry) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .shrinksTabBar()
    }

    /// La legenda della carta, sempre: una linea tratteggiata senza spiegazione si
    /// legge come «da fare», che per una crociera finita è il contrario del vero.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            legendRow(dashed: false, text: Text("registrata"))
            legendRow(dashed: true, text: Text("fra gli scali"))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x041524).opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
        .accessibilityHidden(true)
    }

    private func legendRow(dashed: Bool, text: Text) -> some View {
        HStack(spacing: 6) {
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(path, with: .color(dashed ? Color(hex: 0xDCEBF7).opacity(0.8) : ChartInk.route),
                               style: StrokeStyle(lineWidth: dashed ? 1.5 : 2, lineCap: .round,
                                                  dash: dashed ? [3, 4] : []))
            }
            .frame(width: 18, height: 6)
            text
        }
    }

    private func records(_ entry: LoggedVoyage) -> [RecordTiles.Tile] {
        var tiles: [RecordTiles.Tile] = []
        if let leg = entry.legs(track: track).max(by: { $0.nauticalMiles < $1.nauticalMiles }) {
            tiles.append(.init(glyph: "arrow.left.and.right", title: String(localized: "Più lunga"),
                               value: Format.nauticalMiles(leg.nauticalMiles),
                               detail: "\(leg.from.name) → \(leg.to.name)"))
        }
        if let north = entry.northernmost {
            tiles.append(.init(glyph: "arrow.up", title: String(localized: "Più a nord"),
                               value: Format.latitude(north.coordinate), detail: north.name))
        }
        // La velocità si ricava solo da una rotta registrata: senza, il terzo posto
        // va al punto più a sud.
        if let speed = track?.topSpeed() {
            tiles.append(.init(glyph: "gauge.with.dots.needle.67percent", title: String(localized: "Più veloce"),
                               value: Format.speed(knots: speed.knots, unit: .knots),
                               detail: Format.dayMonth(speed.at, clock: entry.clock)))
        } else if let south = entry.southernmost, south != entry.northernmost {
            tiles.append(.init(glyph: "arrow.down", title: String(localized: "Più a sud"),
                               value: Format.latitude(south.coordinate), detail: south.name))
        }
        return tiles
    }

    private func actions(_ entry: LoggedVoyage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.track != nil {
                Button { confirmingTrackRemoval = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Togli solo la rotta").font(TicketType.rowTitle).foregroundStyle(livery.ink)
                        Text("Miglia e timbri restano").font(TicketType.rowDetail).foregroundStyle(livery.field)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                TicketRule()
            }
            Button(role: .destructive) { confirmingRemoval = true } label: {
                Text("Togli dal diario").font(TicketType.rowTitle)
                    .foregroundStyle(Color(light: 0xB42318, dark: 0xFF8A80))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .paperCard()
        .padding(.top, 8)
    }
}

/// Il biglietto della crociera: nave, date, miglia; sulla matrice imbarco e sbarco.
private struct LoggedVoyageTicket: View {
    @Environment(\.livery) private var livery
    let entry: LoggedVoyage
    let track: Track?
    let isCurrent: Bool

    var body: some View {
        Ticket {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    (isCurrent ? Text("In corso") : Text("Crociera conclusa"))
                        .ticketEyebrow(isCurrent ? livery.signalInk : livery.field)
                    Spacer(minLength: 8)
                    if entry.nights > 0 {
                        Text(entry.nights == 1 ? String(localized: "1 notte")
                                               : String(localized: "\(entry.nights) notti"))
                            .ticketFieldLabel(livery.field)
                    }
                }
                Text(entry.shipName.isEmpty ? String(localized: "Senza nome") : entry.shipName)
                    .font(.system(.largeTitle, weight: .black).width(.condensed))
                    .textCase(.uppercase)
                    .foregroundStyle(livery.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let start = entry.start, let end = entry.end {
                    Text(Format.dateRange(from: start, to: end, clock: entry.clock))
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.field)
                }
                TicketMatrix(fields: [
                    TicketField(label: String(localized: "Miglia"), value: Format.nauticalMiles(entry.nauticalMiles)),
                    TicketField(label: String(localized: "Porti"), value: "\(entry.ports.count)"),
                    TicketField(label: String(localized: "Giorni di mare"), value: "\(entry.seaDays)"),
                ], columns: 3)
                .padding(.top, 10)
                Text(trackNote)
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.field)
                    .padding(.top, 4)
            }
            .padding(18)
        } stub: {
            HStack(alignment: .top, spacing: 14) {
                if let first = entry.ports.first {
                    end(label: Text("Imbarco"), port: first)
                }
                if !isCurrent, entry.ports.count > 1, let last = entry.ports.last {
                    end(label: Text("Sbarco"), port: last)
                }
            }
            .padding(18)
        }
    }

    private func end(label: Text, port: LoggedPort) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label.ticketFieldLabel(livery.field)
            Text(port.name).font(TicketType.fieldValue).foregroundStyle(livery.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(Format.dayMonth(port.arrival, clock: entry.clock)) · \(entry.clock.time(port.arrival))")
                .font(TicketType.rowDetail).foregroundStyle(livery.field)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Da dove vengono le miglia, detto in chiaro. Si guarda il disegno e non le
    /// tratte: una tratta si conta registrata se il telefono ne ha visto almeno
    /// metà, ma la metà che manca sulla carta è tratteggiata, e la frase deve dire
    /// la stessa cosa che si vede.
    private var trackNote: String {
        let sketch = entry.routeSketch(track: track)
        if sketch.recorded.isEmpty {
            return String(localized: "Rotta non registrata: le miglia sono in linea retta fra gli scali.")
        }
        if sketch.gaps.isEmpty {
            return String(localized: "Rotta registrata dal telefono, tutta.")
        }
        return String(localized: "Rotta registrata dal telefono, tranne i tratti tratteggiati.")
    }
}

/// I giorni uno per riga, sulla rotaia come l'Itinerario, tutti già passati.
private struct LoggedDays: View {
    @Environment(\.livery) private var livery
    let entry: LoggedVoyage
    let track: Track?
    let through: Date?
    let isCurrent: Bool

    var body: some View {
        let days = entry.days(track: track, through: through)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                LoggedDayRow(day: day, entry: entry,
                             isFirst: index == 0, isLast: index == days.count - 1,
                             isDisembarkation: !isCurrent && index == days.count - 1,
                             rotation: [-10.0, 7, -5, 9, -8, 4][index % 6])
            }
        }
    }
}

private struct LoggedDayRow: View {
    @Environment(\.livery) private var livery
    @Environment(\.dynamicTypeSize) private var typeSize
    let day: LoggedVoyage.Day
    let entry: LoggedVoyage
    let isFirst: Bool
    let isLast: Bool
    let isDisembarkation: Bool
    let rotation: Double

    private let nodeY: CGFloat = 20

    private var date: Date {
        switch day {
        case .port(let port, _): port.arrival
        case .sea(let date, _): date
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    Text(Format.weekdayAbbreviation(date, clock: entry.clock))
                        .ticketFieldLabel(livery.onHullMuted)
                    Text(Format.dayNumber(date, clock: entry.clock))
                        .font(.system(.title2, weight: .black).width(.condensed))
                        .monospacedDigit()
                        .foregroundStyle(livery.onHull)
                }
                .frame(width: 38)
                .accessibilityElement(children: .combine)
            }
            rail.frame(width: 22)
            row
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var row: some View {
        switch day {
        case .port(let port, let leg):
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if typeSize.isAccessibilitySize { dateLine }
                    Text(port.name)
                        .font(TicketType.place).tracking(0.4).textCase(.uppercase)
                        .foregroundStyle(livery.onHull)
                        .lineLimit(2)
                    Text(detail(port: port, leg: leg))
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.onHullMuted)
                }
                Spacer(minLength: 0)
                MiniStamp(name: port.name, rotation: rotation)
            }
        case .sea(_, let leg):
            VStack(alignment: .leading, spacing: 2) {
                if typeSize.isAccessibilitySize { dateLine }
                Text("Giorno di mare")
                    .font(TicketType.rowTitle)
                    .foregroundStyle(livery.onHull.opacity(0.85))
                if let leg {
                    Text(seaDetail(leg))
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.onHullMuted)
                }
            }
        }
    }

    private var dateLine: some View {
        Text("\(Format.weekdayAbbreviation(date, clock: entry.clock)) \(Format.dayNumber(date, clock: entry.clock))")
            .font(.system(.title3, weight: .black).width(.condensed))
            .foregroundStyle(livery.onHull)
    }

    private func detail(port: LoggedPort, leg: LoggedVoyage.Leg?) -> String {
        let time = entry.clock.time(port.arrival)
        var parts: [String]
        if isFirst {
            parts = [String(localized: "imbarco · \(time)")]
        } else if isDisembarkation {
            parts = [String(localized: "sbarco · \(time)")]
        } else {
            parts = [String(localized: "arrivo \(time)")]
        }
        if let leg {
            parts.append(Format.nauticalMiles(leg.nauticalMiles))
            if !leg.isRecorded { parts.append(String(localized: "senza rotta")) }
        }
        return parts.joined(separator: " · ")
    }

    private func seaDetail(_ leg: LoggedVoyage.Leg) -> String {
        var text = String(localized: "Verso \(leg.to.name) · \(Format.nauticalMiles(leg.nauticalMiles))")
        if !leg.isRecorded { text += " · " + String(localized: "senza rotta") }
        return text
    }

    private var rail: some View {
        Canvas { context, size in
            let x = size.width / 2
            var path = Path()
            if !isFirst { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: nodeY - 8)) }
            if !isLast { path.move(to: CGPoint(x: x, y: nodeY + 8)); path.addLine(to: CGPoint(x: x, y: size.height)) }
            context.stroke(path, with: .color(livery.onHull.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let isPort = if case .port = day { true } else { false }
            let r: CGFloat = isPort ? 7 : 4.5
            let dot = Path(ellipseIn: CGRect(x: x - r, y: nodeY - r, width: r * 2, height: r * 2))
            if isPort {
                context.fill(dot, with: .color(livery.onHullMuted))
                var tick = Path()
                tick.move(to: CGPoint(x: x - 3, y: nodeY))
                tick.addLine(to: CGPoint(x: x - 0.8, y: nodeY + 2.2))
                tick.addLine(to: CGPoint(x: x + 3.2, y: nodeY - 2.2))
                context.stroke(tick, with: .color(livery.hull), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            } else {
                context.fill(dot, with: .color(livery.hull))
                context.stroke(dot, with: .color(livery.onHullMuted), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Il timbro del porto in piccolo, accanto alla riga: la stessa forma e lo stesso
/// inchiostro della pagina del passaporto, così la riga e il timbro si ritrovano.
/// Sullo scafo scuro l'inchiostro è quello schiarito della carta scura.
private struct MiniStamp: View {
    @Environment(\.livery) private var livery
    let name: String
    let rotation: Double

    var body: some View {
        let ink = Color(hex: livery.stampInkPair(StampInk.of(name)).dark)
        Text(String(name.prefix(3)))
            .font(.system(size: 10, weight: .black).width(.condensed))
            .textCase(.uppercase)
            .foregroundStyle(ink)
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(ink, lineWidth: 1.6))
            .overlay(Circle().stroke(ink, lineWidth: 0.6).padding(3.5))
            .rotationEffect(.degrees(rotation))
            .opacity(0.9)
            .accessibilityHidden(true)
    }
}

/// I primati in schede affiancate: il numero grande, si leggono in un colpo.
/// Ai corpi accessibili una sotto l'altra, se no i numeri si spezzerebbero.
struct RecordTiles: View {
    struct Tile: Identifiable {
        var glyph: String
        var title: String
        var value: String
        var detail: String
        var id: String { title }
    }

    @Environment(\.livery) private var livery
    let tiles: [Tile]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(tiles) { tile($0, compact: true) }
            }
            VStack(spacing: 8) {
                ForEach(tiles) { tile($0, compact: false) }
            }
        }
    }

    private func tile(_ tile: Tile, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: tile.glyph)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(livery.signalInk)
                // Altezza fissa: i glifi hanno altezze diverse, e senza questo le
                // tre schede partivano da righe diverse.
                .frame(height: 18, alignment: .leading)
            Text(tile.title).ticketFieldLabel(livery.field)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(tile.value)
                .font(.system(.title3, weight: .black).width(.condensed))
                .monospacedDigit()
                .foregroundStyle(livery.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(tile.detail)
                .font(.caption2)
                .foregroundStyle(livery.field)
                .lineLimit(compact ? 2 : 3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: compact ? 116 : nil, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .paperCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}
