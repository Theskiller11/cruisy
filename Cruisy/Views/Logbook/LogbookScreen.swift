import SwiftUI

/// Il diario di bordo: il passaporto.
///
/// Non è una schermata operativa — non serve a prendere la nave — quindi non
/// compete con le altre per l'attenzione: qui i numeri possono essere grandi e
/// lenti. In cima le miglia di sempre; poi le crociere, ognuna un biglietto che si
/// apre sulla sua pagina; poi i porti come timbri su una pagina di passaporto e i
/// primati. Si riempie da solo mentre navighi, scalo dopo scalo.
///
/// **Niente carta qui.** C'era, con tutte le rotte insieme: dopo due o tre crociere
/// diventava un gomitolo in cui non se ne leggeva nessuna. La linea percorsa sta
/// nella pagina della sua crociera, e solo lì.
enum LogbookRoute: Hashable {
    case ports
    case voyage(UUID)
}

struct LogbookScreen: View {
    @Environment(VoyageStore.self) private var store
    @Environment(\.livery) private var livery
    @State private var confirmingRemoval: LoggedVoyage?
    /// L'anno mostrato nella scala delle distanze. Nullo = tutto.
    @State private var scaleYear: Int?
    @State private var path: [LogbookRoute] = []

    private var logbook: Logbook { store.logbook.logbook }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                livery.hull.ignoresSafeArea()
                if logbook.isEmpty {
                    EmptyLogbook()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            // La testata è nostra, come in Oggi: il titolo grande di
                            // sistema in modalità chiara veniva blu scuro sullo scafo blu.
                            Masthead(String(localized: "Diario"))
                                .accessibilityIdentifier("diario-testata")
                                .padding(.horizontal, 6)
                                .padding(.top, 8)
                            DistanceScaleCard(logbook: logbook, year: $scaleYear)
                            voyages
                            stamps
                            records
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                    .shrinksTabBar()
                }
            }
            .navigationTitle("Diario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #if DEBUG
            .task {
                guard !logbook.isEmpty else { return }
                switch DebugLaunch.open {
                case "porti": path = [.ports]
                case "crociera":
                    // La prima crociera conclusa, se c'è: è quella che ha la rotta.
                    let past = logbook.voyages.first { $0.id != store.voyage?.id } ?? logbook.voyages.first
                    if let past { path = [.voyage(past.id)] }
                default: break
                }
            }
            #endif
            .navigationDestination(for: LogbookRoute.self) { route in
                switch route {
                case .ports: PortsScreen(stamps: logbook.stamps)
                case .voyage(let id): LoggedVoyageScreen(entryID: id)
                }
            }
            .confirmationDialog("Togliere questa crociera dal diario?",
                                isPresented: Binding(get: { confirmingRemoval != nil },
                                                     set: { if !$0 { confirmingRemoval = nil } }),
                                titleVisibility: .visible) {
                Button("Togli dal diario", role: .destructive) {
                    if let entry = confirmingRemoval { store.logbook.forget(entry) }
                    confirmingRemoval = nil
                }
                Button("Annulla", role: .cancel) { confirmingRemoval = nil }
            } message: {
                Text("Le miglia e i porti di questa crociera spariranno dai totali.")
            }
        }
    }

    // MARK: Le crociere

    private var voyages: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Le tue crociere")
                .ticketEyebrow(livery.onHullMuted)
                .padding(.horizontal, 4)
                .padding(.top, 6)
            ForEach(logbook.voyages) { entry in
                let isCurrent = entry.id == store.voyage?.id && store.moment != .completed
                NavigationLink(value: LogbookRoute.voyage(entry.id)) {
                    VoyageStubCard(entry: entry, isCurrent: isCurrent)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Togli dal diario", systemImage: "trash", role: .destructive) {
                        confirmingRemoval = entry
                    }
                }
            }
        }
    }

    // MARK: I timbri

    /// I porti toccati, come timbri sul passaporto.
    ///
    /// **Solo quelli visitati tre volte o più.** Dopo qualche crociera l'elenco
    /// completo diventa un muro in cui non si trova più niente, e un porto visto una
    /// volta sola non dice nulla di chi lo ha visto: quelli che tornano sì. Tutti gli
    /// altri stanno nella pagina dedicata, con le foto.
    ///
    /// Finché di porti abituali non ce n'è nessuno si mostrano comunque i più
    /// recenti: una pagina vuota intitolata «Porti toccati» a chi ha appena finito
    /// la prima crociera sembrerebbe un guasto.
    @ViewBuilder
    private var stamps: some View {
        let all = logbook.stamps
        let regulars = all.filter { $0.visits >= 3 }
        let shown = regulars.isEmpty ? Array(all.prefix(6)) : Array(regulars.prefix(6))
        let embarkations = Set(logbook.voyages.compactMap { $0.ports.first.map { ShipDirectory.fold($0.name) } })
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(regulars.isEmpty ? "Porti toccati" : "I porti dove torni").ticketEyebrow(livery.signalInk)
                    Spacer(minLength: 8)
                    NavigationLink(value: LogbookRoute.ports) {
                        HStack(spacing: 3) {
                            Text("Tutti e \(all.count)").ticketFieldLabel(livery.field)
                            PaperDisclosure()
                        }
                    }
                    .buttonStyle(.plain)
                }
                PassportPage(entries: shown.map { stamp in
                    // Il timbro dice la prima volta: ogni porto ha l'ora di bordo
                    // della crociera in cui ci sei arrivato.
                    let clock = logbook.voyages.first { $0.ports.contains(stamp.port) }?.clock
                        ?? ShipClock(secondsFromGMT: 0)
                    return PassportPage.Entry(
                        name: stamp.port.name, date: stamp.port.arrival, clock: clock, visits: stamp.visits,
                        kind: embarkations.contains(stamp.id) ? .embarkation : .arrival)
                })
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { Guilloche() }
            .paperCard()
        }
    }

    // MARK: I primati

    @ViewBuilder
    private var records: some View {
        let tiles = recordTiles
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Primati").ticketEyebrow(livery.onHullMuted)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                RecordTiles(tiles: tiles)
            }
        }
    }

    private var recordTiles: [RecordTiles.Tile] {
        var tiles: [RecordTiles.Tile] = []
        if let crossing = logbook.longestCrossing, crossing.nauticalMiles > 0 {
            tiles.append(.init(glyph: "arrow.left.and.right", title: String(localized: "Più lunga"),
                               value: Format.nauticalMiles(crossing.nauticalMiles),
                               detail: "\(crossing.from.name) → \(crossing.to.name)"))
        }
        if let north = logbook.northernmost {
            tiles.append(.init(glyph: "arrow.up", title: String(localized: "Più a nord"),
                               value: Format.latitude(north.coordinate), detail: north.name))
        }
        if let south = logbook.southernmost, south != logbook.northernmost {
            tiles.append(.init(glyph: "arrow.down", title: String(localized: "Più a sud"),
                               value: Format.latitude(south.coordinate), detail: south.name))
        }
        return tiles
    }
}

/// Una crociera nel diario: la matrice strappata. A sinistra la nave, le date e la
/// rotta in piccolo; sul tagliando a destra le miglia.
private struct VoyageStubCard: View {
    @Environment(\.livery) private var livery
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: LoggedVoyage
    let isCurrent: Bool

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Ai corpi accessibili il tagliando a destra non ha spazio: va sotto,
                // come la matrice di un biglietto normale.
                Ticket { main.padding(16) } stub: { miles.padding(16) }
            } else {
                HStack(spacing: 0) {
                    main.padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 14)
                    VerticalPerforation()
                    miles.frame(width: 104).padding(.vertical, 14)
                }
                .background(StubShape(stubWidth: 104).fill(livery.paper))
                .clipShape(StubShape(stubWidth: 104))
                .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Apre la pagina della crociera"))
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.shipName.isEmpty ? String(localized: "Senza nome") : entry.shipName)
                    .font(TicketType.place)
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                PaperDisclosure()
            }
            if let start = entry.start, let end = entry.end {
                Text(Format.dateRange(from: start, to: end, clock: entry.clock))
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.field)
            }
            MiniRoute(ports: entry.ports, isCurrent: isCurrent)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var miles: some View {
        VStack(spacing: 4) {
            if isCurrent { StampBadge(String(localized: "In corso")) }
            Text(Format.nauticalMiles(entry.nauticalMiles))
                .font(.system(.title2, weight: .black).width(.condensed))
                .monospacedDigit()
                .foregroundStyle(livery.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(entry.ports.count == 1 ? String(localized: "1 porto") : String(localized: "\(entry.ports.count) porti"))
                .ticketFieldLabel(livery.field)
            Text(entry.seaDays == 1 ? String(localized: "1 giorno di mare")
                                    : String(localized: "\(entry.seaDays) giorni di mare"))
                .font(.caption2)
                .foregroundStyle(livery.field)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }
}

/// La rotta in piccolo: un punto per porto, il primo e l'ultimo col nome.
private struct MiniRoute: View {
    @Environment(\.livery) private var livery
    let ports: [LoggedPort]
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                let count = max(ports.count, 1)
                let width = geometry.size.width - 8
                ZStack(alignment: .leading) {
                    Capsule().fill(livery.ink).frame(height: 2).padding(.horizontal, 4)
                    ForEach(0..<count, id: \.self) { index in
                        let end = index == 0 || index == count - 1
                        let now = isCurrent && index == count - 1
                        Circle()
                            .fill(now ? livery.signal : livery.ink)
                            .overlay(Circle().stroke(livery.paper, lineWidth: 1.2))
                            .frame(width: end ? 9 : 6, height: end ? 9 : 6)
                            .position(x: 4 + (count == 1 ? 0 : width * CGFloat(index) / CGFloat(count - 1)),
                                      y: geometry.size.height / 2)
                    }
                }
            }
            .frame(height: 10)
            HStack(alignment: .firstTextBaseline) {
                Text(ports.first?.name ?? "")
                Spacer(minLength: 6)
                if ports.count > 1 { Text(ports.last?.name ?? "") }
            }
            .font(TicketType.fieldLabel)
            .foregroundStyle(livery.ink)
            .lineLimit(1)
        }
        .accessibilityHidden(true)
    }
}

/// La perforazione verticale fra la crociera e il tagliando delle miglia.
private struct VerticalPerforation: View {
    @Environment(\.livery) private var livery
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: 14))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height - 14))
            context.stroke(path, with: .color(livery.perforation),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .frame(width: 2)
        .accessibilityHidden(true)
    }
}

/// Il biglietto col tagliando a destra: gli incavi sopra e sotto, dove passa la
/// perforazione. Sono buchi veri, come in `TicketShape`.
private struct StubShape: Shape {
    let stubWidth: CGFloat
    var radius: CGFloat = 16
    var notch: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let paper = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        let x = rect.maxX - stubWidth - 1
        var notches = Path()
        notches.addEllipse(in: CGRect(x: x - notch, y: rect.minY - notch, width: notch * 2, height: notch * 2))
        notches.addEllipse(in: CGRect(x: x - notch, y: rect.maxY - notch, width: notch * 2, height: notch * 2))
        return paper.subtracting(notches)
    }
}

/// Il diario vuoto non si scusa: dice quando si riempirà, e che cosa ci finirà.
private struct EmptyLogbook: View {
    @Environment(VoyageStore.self) private var store
    @Environment(\.livery) private var livery

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Masthead(String(localized: "Diario"))
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                cover
                    .padding(.vertical, 12)
                VStack(spacing: 6) {
                    Text("Il diario è ancora bianco")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(livery.onHull)
                    Text(firstStamp)
                        .font(.subheadline)
                        .foregroundStyle(livery.onHullMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                whatGoesIn
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .shrinksTabBar()
    }

    /// La copertina di un passaporto chiuso, col nome della nave se c'è, e un
    /// timbro tratteggiato che aspetta.
    private var cover: some View {
        VStack(spacing: 10) {
            Image(systemName: "ferry.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(livery.signalOnHull)
                .frame(width: 70, height: 70)
                .overlay(Circle().stroke(livery.signalOnHull, lineWidth: 1.5))
                .overlay(Circle().stroke(livery.signalOnHull, lineWidth: 0.6).padding(5))
            Text("Diario di bordo")
                .font(.system(.subheadline, weight: .black).width(.condensed))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(livery.signalOnHull)
            if let ship = store.voyage?.shipName, !ship.isEmpty {
                Rectangle().fill(livery.signalOnHull).frame(width: 70, height: 0.8)
                Text(ship)
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.onHull.opacity(0.75))
            }
        }
        .frame(width: 168, height: 220)
        .background(RoundedRectangle(cornerRadius: 12).fill(livery.hullDeep))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(livery.onHull.opacity(0.14)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
        .rotationEffect(.degrees(-4))
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Text("Il primo")
                Text("timbro")
            }
            .font(.system(.caption2, weight: .black))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(livery.onHullMuted)
            .frame(width: 76, height: 76)
            .background(Circle().fill(livery.hull))
            .overlay(Circle().stroke(livery.onHullMuted, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])))
            .rotationEffect(.degrees(12))
            .offset(x: 44, y: 18)
        }
        .accessibilityHidden(true)
    }

    /// Quando arriva il primo timbro, con il porto e l'ora veri della crociera.
    private var firstStamp: String {
        guard let voyage = store.voyage,
              let next = voyage.calls.first(where: { $0.arrival > store.now }) else {
            return String(localized: "Ogni porto in cui arrivi ci finisce da solo, con le miglia percorse per raggiungerlo.")
        }
        return String(localized: "Si riempie da solo. Il primo timbro arriva a \(next.name), \(Format.dayMonth(next.arrival, clock: voyage.clock)) alle \(voyage.clock.time(next.arrival)).")
    }

    private var whatGoesIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cosa ci finirà").ticketEyebrow(livery.signalInk)
            row(Text("Le miglia"), Text("contate mentre navighi, messe in scala"))
            row(Text("Un timbro per porto"), Text("con la data, come sul passaporto"))
            row(Text("I primati"), Text("la traversata più lunga, il punto più a nord"))
            row(Text("La rotta di ogni crociera"), Text("se registri la posizione, sulla sua pagina"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }

    private func row(_ title: Text, _ detail: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().stroke(livery.signal, lineWidth: 1.5).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                title.font(TicketType.rowTitle).foregroundStyle(livery.ink)
                detail.font(TicketType.rowDetail).foregroundStyle(livery.field)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
