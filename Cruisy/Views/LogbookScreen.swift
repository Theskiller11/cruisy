import SwiftUI

/// Il diario di bordo: quello che resta quando la crociera è finita.
///
/// Non è una schermata operativa — non serve a prendere la nave — quindi non
/// compete con le altre per l'attenzione: qui i numeri possono essere grandi e
/// lenti. Si riempie da solo mentre navighi, scalo dopo scalo.
/// Dove può portare il diario.
enum LogbookRoute: Hashable { case ports }

struct LogbookScreen: View {
    @Environment(VoyageStore.self) private var store
    @State private var confirmingRemoval: LoggedVoyage?
    /// L'anno mostrato nella scala delle distanze. Nullo = tutto.
    @State private var scaleYear: Int?
    @State private var path: [LogbookRoute] = []

    private var logbook: Logbook { store.logbook.logbook }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Palette.seaBackground.ignoresSafeArea()
                if logbook.isEmpty {
                    EmptyLogbook()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            DistanceScaleCard(logbook: logbook, year: $scaleYear)
                                .padding(.top, 8)
                            totals
                            records
                            stamps
                            voyages
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 96)
                    }
                }
            }
            .navigationTitle("Diario")
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

    // MARK: I totali

    /// I tre conteggi. **Le miglia non stanno più qui**: le ha prese la card della
    /// scala, che sa anche dire quanto valgono. Ripeterle a tre centimetri di
    /// distanza sarebbe rumore, e toglierebbe spazio a quello che manca.
    private var totals: some View {
        VStack(spacing: 14) {
            MetricRow(metrics: [
                Metric(value: "\(logbook.seaDays)",
                       label: logbook.seaDays == 1 ? String(localized: "Giorno di mare")
                                                   : String(localized: "Giorni di mare")),
                Metric(value: "\(logbook.stamps.count)",
                       label: logbook.stamps.count == 1 ? String(localized: "Porto")
                                                        : String(localized: "Porti")),
                Metric(value: "\(logbook.voyages.count)",
                       label: logbook.voyages.count == 1 ? String(localized: "Crociera")
                                                         : String(localized: "Crociere")),
            ])
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 28, prominence: .card)
        .accessibilityElement(children: .combine)
    }

    // MARK: I primati

    @ViewBuilder
    private var records: some View {
        let rows = recordRows
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().overlay(Palette.hairline) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: row.glyph)
                            .font(.footnote)
                            .foregroundStyle(Palette.underway)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).eyebrow()
                            Text(row.detail)
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkPrimary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .glassSurface(cornerRadius: 24, prominence: .card)
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

    // MARK: I timbri

    @ViewBuilder
    /// I porti toccati.
    ///
    /// **Solo quelli visitati tre volte o più.** Dopo qualche crociera l'elenco
    /// completo diventa un muro di pastiglie in cui non si trova più niente, e un
    /// porto visto una volta sola non dice nulla di chi lo ha visto: quelli che
    /// tornano sì. Tutti gli altri stanno nella schermata dedicata, con le foto.
    ///
    /// Finché di porti abituali non ce n'è nessuno si mostrano comunque i più
    /// recenti: un riquadro vuoto intitolato "Porti toccati" a chi ha appena finito
    /// la prima crociera sembrerebbe un guasto.
    private var stamps: some View {
        let all = logbook.stamps
        let regulars = all.filter { $0.visits >= 3 }
        let shown = regulars.isEmpty ? Array(all.prefix(8)) : regulars
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(regulars.isEmpty ? "Porti toccati" : "I porti dove torni").eyebrow()
                    Spacer(minLength: 8)
                    NavigationLink(value: LogbookRoute.ports) {
                        HStack(spacing: 3) {
                            Text("Tutti e \(all.count)")
                                .font(Type.metricLabel.weight(.semibold))
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Palette.action)
                    }
                    .buttonStyle(.plain)
                }
                FlowRow(spacing: 7) {
                    ForEach(shown) { stamp in
                        HStack(spacing: 5) {
                            Text(stamp.port.name)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.inkPrimary)
                            if stamp.visits > 1 {
                                Text("×\(stamp.visits)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Palette.underway)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Palette.ink.opacity(0.07)))
                        .overlay(Capsule().stroke(Palette.hairline, lineWidth: 0.5))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(stamp.visits > 1
                            ? Text("\(stamp.port.name), \(stamp.visits) volte")
                            : Text(stamp.port.name))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 24, prominence: .card)
        }
    }

    // MARK: Le crociere

    private var voyages: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Le tue crociere").eyebrow()
            ForEach(logbook.voyages) { entry in
                VoyageEntryCard(entry: entry, isCurrent: entry.id == store.voyage?.id)
                    .contextMenu {
                        Button("Togli dal diario", systemImage: "trash", role: .destructive) {
                            confirmingRemoval = entry
                        }
                    }
            }
        }
    }
}

/// Una crociera nel diario.
private struct VoyageEntryCard: View {
    let entry: LoggedVoyage
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.shipName.isEmpty ? String(localized: "Senza nome") : entry.shipName)
                    .font(.headline)
                    .foregroundStyle(Palette.inkPrimary)
                if isCurrent {
                    Text("in corso")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.underway)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.underway.opacity(0.14)))
                }
                Spacer(minLength: 0)
            }

            if let start = entry.start, let end = entry.end {
                Text(Format.dateRange(from: start, to: end, clock: entry.clock))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }

            Text(entry.ports.map(\.name).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Palette.inkTertiary)
                .lineLimit(3)

            HStack(spacing: 14) {
                Label(Format.nauticalMiles(entry.nauticalMiles), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label(entry.seaDays == 1 ? String(localized: "1 giorno in mare")
                                         : String(localized: "\(entry.seaDays) giorni in mare"),
                      systemImage: "water.waves")
            }
            .font(.caption2)
            .foregroundStyle(Palette.inkSecondary)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22, prominence: .card)
        .accessibilityElement(children: .combine)
    }
}

/// Il diario vuoto non si scusa: dice quando si riempirà.
private struct EmptyLogbook: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.inkTertiary)
            Text("Il diario è ancora bianco")
                .font(.headline)
                .foregroundStyle(Palette.inkPrimary)
            Text("Ogni porto in cui arrivi ci finisce da solo, con le miglia percorse per raggiungerlo.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
