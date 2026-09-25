import SwiftUI

/// Il diario di bordo: il passaporto.
///
/// Non è una schermata operativa — non serve a prendere la nave — quindi non
/// compete con le altre per l'attenzione: qui i numeri possono essere grandi e
/// lenti. I porti toccati sono timbri su una pagina; le crociere, matrici di
/// biglietti conservate. Si riempie da solo mentre navighi, scalo dopo scalo.
enum LogbookRoute: Hashable { case ports }

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
                            stamps
                            records
                            voyages
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
            .task { if DebugLaunch.open == "porti", !logbook.isEmpty { path = [.ports] } }
            #endif
            .navigationDestination(for: LogbookRoute.self) { route in
                switch route {
                case .ports: PortsScreen(stamps: logbook.stamps)
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
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
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
                StampPage(stamps: shown, clock: ShipClock(secondsFromGMT: 0))
                    .padding(.horizontal, 6)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard()
        }
    }

    // MARK: I primati

    @ViewBuilder
    private var records: some View {
        let rows = recordRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Primati").ticketEyebrow(livery.signalInk)
                    .padding(.bottom, 6)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { TicketRule() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: row.glyph)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(livery.field)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).ticketFieldLabel(livery.field)
                            Text(row.detail)
                                .font(TicketType.fieldValue)
                                .foregroundStyle(livery.ink)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .paperCard()
        }
    }

    private struct RecordRow {
        var glyph: String
        var title: String
        var detail: String
    }

    private var recordRows: [RecordRow] {
        var rows: [RecordRow] = []
        if let crossing = logbook.longestCrossing, crossing.nauticalMiles > 0 {
            rows.append(RecordRow(
                glyph: "arrow.left.and.right",
                title: String(localized: "Traversata più lunga"),
                detail: "\(crossing.from.name) → \(crossing.to.name) · \(Format.nauticalMiles(crossing.nauticalMiles))"))
        }
        if let north = logbook.northernmost {
            rows.append(RecordRow(glyph: "arrow.up", title: String(localized: "Punto più a nord"),
                                  detail: "\(north.name) · \(Format.latitude(north.coordinate))"))
        }
        if let south = logbook.southernmost, south != logbook.northernmost {
            rows.append(RecordRow(glyph: "arrow.down", title: String(localized: "Punto più a sud"),
                                  detail: "\(south.name) · \(Format.latitude(south.coordinate))"))
        }
        let ships = logbook.ships
        if !ships.isEmpty {
            rows.append(RecordRow(glyph: "ferry.fill",
                                  title: ships.count == 1 ? String(localized: "Nave") : String(localized: "Navi"),
                                  detail: ships.joined(separator: ", ")))
        }
        return rows
    }

    // MARK: Le crociere

    private var voyages: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Le tue crociere")
                .ticketEyebrow(livery.onHullMuted)
                .padding(.horizontal, 4)
            ForEach(logbook.voyages) { entry in
                VoyageStubCard(entry: entry, isCurrent: entry.id == store.voyage?.id)
                    .contextMenu {
                        Button("Togli dal diario", systemImage: "trash", role: .destructive) {
                            confirmingRemoval = entry
                        }
                    }
            }
        }
    }
}

/// I timbri dei porti, in una pagina: ognuno un cerchio inclinato a modo suo.
///
/// Tutti dello **stesso diametro**, in una griglia che li contiene con margine: al
/// primo giro i timbri si allargavano sul nome, «CHARLOTTE AMALIE» usciva dalla
/// carta e l'anno finiva sopra il timbro accanto. Qui il cerchio è fisso, il nome
/// va a capo sulle parole e, se una parola è lunga, si stringe.
struct StampPage: View {
    @Environment(\.livery) private var livery
    @ScaledMetric(relativeTo: .caption2) private var scaledDiameter: CGFloat = 92
    let stamps: [Logbook.Stamp]
    let clock: ShipClock

    private var diameter: CGFloat { min(scaledDiameter, 128) }

    var body: some View {
        // Le celle sono un po' più strette dei timbri: due vicini si sfiorano e si
        // accavallano di poco, come su un passaporto. La carta attorno ha margine
        // perché nessuno esca dal bordo, nemmeno inclinato.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: diameter - 8), spacing: 0)], spacing: 4) {
            ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                // Inclinazioni diverse, ma **fisse**: un timbro che gira a ogni
                // ridisegno non è un timbro.
                let rotation = [-11.0, 7.0, -5.0, 9.0, -8.0, 4.0][index % 6]
                VStack(spacing: 6) {
                    Stamp(stampText(stamp), color: stamp.visits >= 3 ? livery.signal : livery.field,
                          rotation: rotation, diameter: diameter)
                    Text(String(clock.calendar(at: stamp.port.arrival).component(.year, from: stamp.port.arrival)))
                        .font(TicketType.fieldLabel)
                        .foregroundStyle(livery.field)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(stamp.visits > 1
                    ? Text("\(stamp.port.name), \(stamp.visits) volte")
                    : Text(stamp.port.name))
            }
        }
    }

    /// Il nome spezzato sulle parole, una per riga, e le visite in fondo.
    private func stampText(_ stamp: Logbook.Stamp) -> String {
        let words = stamp.port.name.split(separator: " ").map(String.init)
        var lines: [String] = []
        for word in words {
            // Due parole corte stanno sulla stessa riga: «SAN JUAN», non «SAN / JUAN».
            if let last = lines.last, last.count + word.count + 1 <= 9 {
                lines[lines.count - 1] = last + " " + word
            } else {
                lines.append(word)
            }
        }
        if stamp.visits > 1 { lines.append("×\(stamp.visits)") }
        return lines.prefix(3).joined(separator: "\n")
    }
}

/// Una crociera nel diario: la matrice del biglietto che resta.
private struct VoyageStubCard: View {
    @Environment(\.livery) private var livery
    let entry: LoggedVoyage
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.shipName.isEmpty ? String(localized: "Senza nome") : entry.shipName)
                    .font(TicketType.place)
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.ink)
                if isCurrent {
                    StampBadge(String(localized: "In corso"))
                }
                Spacer(minLength: 0)
            }

            if let start = entry.start, let end = entry.end {
                Text(Format.dateRange(from: start, to: end, clock: entry.clock))
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.field)
            }

            Text(entry.ports.map(\.name).joined(separator: " · "))
                .font(TicketType.rowDetail)
                .foregroundStyle(livery.ink)
                .lineLimit(3)

            TicketRule()

            TicketMatrix(fields: [
                TicketField(label: String(localized: "Miglia"), value: Format.nauticalMiles(entry.nauticalMiles)),
                TicketField(label: String(localized: "Giorni di mare"), value: "\(entry.seaDays)"),
                TicketField(label: String(localized: "Porti"), value: "\(entry.ports.count)"),
            ], columns: 3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
        .accessibilityElement(children: .combine)
    }
}

/// Il diario vuoto non si scusa: dice quando si riempirà.
private struct EmptyLogbook: View {
    @Environment(\.livery) private var livery

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(livery.onHullMuted)
            Text("Il diario è ancora bianco")
                .font(.headline)
                .foregroundStyle(livery.onHull)
            Text("Ogni porto in cui arrivi ci finisce da solo, con le miglia percorse per raggiungerlo.")
                .font(.subheadline)
                .foregroundStyle(livery.onHullMuted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
