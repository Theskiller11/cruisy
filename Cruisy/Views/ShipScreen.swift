import SwiftUI

/// La scheda della nave: le carte di bordo.
///
/// Si riempie da sola dal nome: i dati vengono da Wikidata, che è **CC0** — stazza,
/// lunghezza, numero IMO, anno di consegna sono fatti, e i fatti non appartengono a
/// nessuno. Il piano dei ponti invece resta fuori: quello è materiale della
/// compagnia. Il nome della compagnia compare qui **come dato**, e solo qui.
struct ShipScreen: View {
    @Environment(VoyageStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.livery) private var livery
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photos = ShipPhotoService()
    @Environment(Reachability.self) private var reachability
    @Environment(ShipLookupService.self) private var lookup

    private var record: ShipRecord? { store.shipRecord }

    var body: some View {
        NavigationStack {
            ZStack {
                livery.hull.ignoresSafeArea()
                if let voyage = store.voyage {
                    content(voyage: voyage)
                } else {
                    NoVoyageView()
                }
            }
            .navigationTitle("Nave")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func content(voyage: Voyage) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                photo(voyage: voyage)

                Masthead(record?.name ?? voyage.shipName,
                         detail: record?.operatorName.isEmpty == false ? record?.operatorName : nil)
                    .padding(.horizontal, 6)

                papers(voyage: voyage)

                liveryRow

                if record == nil {
                    missingShip(name: voyage.shipName)
                }

                sourceNote
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .task(id: "\(record?.imageFile ?? "")|\(reachability.isExpensive)") {
            if let record {
                await photos.load(record, allowsDownload: PhotoDownloadPolicy.allows(isMetered: reachability.isExpensive))
            }
        }
    }

    // MARK: La foto

    @ViewBuilder
    private func photo(voyage: Voyage) -> some View {
        if let photo = photos.photo {
            ShipPhotoCard(photo: photo)
        } else {
            // Senza foto non si lascia un buco: si disegna la rotta, che è un
            // contenuto vero e sempre disponibile.
            ZStack {
                SeaChart(voyage: voyage, fix: nil, now: store.now,
                         framing: .wholeVoyage, showsPortNames: false,
                         showsGraticule: true, showsShip: false, padding: 26)
                if photos.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(6)
            .paperCard()
            .accessibilityLabel(Text("La rotta della crociera"))
        }
    }

    // MARK: Le carte di bordo

    /// Stazza, misure, anno, bandiera, identificativi: la matrice delle carte.
    @ViewBuilder
    private func papers(voyage: Voyage) -> some View {
        let fields = paperFields(voyage: voyage)
        if !fields.isEmpty {
            Ticket {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Carte di bordo").ticketEyebrow(livery.signalInk)
                    Text(record?.name ?? voyage.shipName)
                        .font(.system(.largeTitle, weight: .black).width(.condensed))
                        .textCase(.uppercase)
                        .foregroundStyle(livery.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)
            } stub: {
                TicketMatrix(fields: fields, columns: 2)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
            }
        }
    }

    private func paperFields(voyage: Voyage) -> [TicketField] {
        var fields: [TicketField] = []
        if let record {
            if record.tonnage > 0 {
                fields.append(TicketField(label: String(localized: "Stazza"), value: Format.tonnage(record.tonnage)))
            }
            if record.length > 0 {
                fields.append(TicketField(label: String(localized: "Lunghezza"), value: "\(Int(record.length)) m"))
            }
            if record.beam > 0 {
                fields.append(TicketField(label: String(localized: "Larghezza"), value: "\(Int(record.beam)) m"))
            }
            if record.year > 0 {
                fields.append(TicketField(label: String(localized: "In servizio"), value: "\(record.year)"))
            }
            if !record.flag.isEmpty {
                fields.append(TicketField(label: String(localized: "Bandiera"), value: record.flag))
            }
        }
        let imo = record?.imo.isEmpty == false ? record?.imo : voyage.imo
        let mmsi = record?.mmsi.isEmpty == false ? record?.mmsi : voyage.mmsi
        if let imo { fields.append(TicketField(label: "IMO", value: imo)) }
        if let mmsi { fields.append(TicketField(label: "MMSI", value: mmsi)) }
        return fields
    }

    /// La livrea in vigore, e da dove viene. Solo come informazione: si cambia
    /// nelle Impostazioni, e qui si dice dove.
    @ViewBuilder
    private var liveryRow: some View {
        let fromCompany = preferences.livery == .company && livery != .cruisy
        PaperRow(glyph: "paintpalette",
                 title: String(localized: "Livrea: \(livery.name)"),
                 subtitle: fromCompany
                    ? String(localized: "Colori ispirati alla compagnia. Si cambia nelle Impostazioni.")
                    : String(localized: "La livrea di Cruisy. Si cambia nelle Impostazioni."))
    }

    /// Quando la nave non è nell'elenco.
    ///
    /// L'elenco impacchettato è una fotografia di Wikidata: una nave varata dopo,
    /// o aggiunta là dopo, non ci sarebbe. Andarla a prendere è un tocco — ma **è**
    /// un tocco, non un effetto collaterale: cercare un nome su un servizio di terzi
    /// è comunque qualcosa che esce dal telefono, e l'app promette di non farlo da sé.
    @ViewBuilder
    private func missingShip(name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch lookup.outcome {
            case .searching:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Cerco «\(name)» su Wikidata…")
                        .font(TicketType.body)
                        .foregroundStyle(livery.field)
                }
            case .notFound:
                Label("Su Wikidata non c'è nessuna nave con questo nome. Controlla come è scritto: conta la grafia, non le maiuscole.",
                      systemImage: "questionmark.circle")
                    .font(TicketType.body)
                    .foregroundStyle(livery.ink)
                retry(name: name)
            case .failed(let reason):
                Label("Non sono riuscito a chiedere a Wikidata: \(reason)",
                      systemImage: "wifi.exclamationmark")
                    .font(TicketType.body)
                    .foregroundStyle(livery.ink)
                retry(name: name)
            default:
                Text("Questa nave non è nell'elenco che viaggia dentro l'app. I countdown funzionano lo stesso: la scheda è un di più.")
                    .font(TicketType.body)
                    .foregroundStyle(livery.ink)
                Button {
                    Task { await lookup.search(name) }
                } label: {
                    Label("Cercala su Wikidata", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(livery.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paperCard()
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func retry(name: String) -> some View {
        Button("Riprova") { Task { await lookup.search(name) } }
            .font(TicketType.rowTitle)
            .tint(livery.ink)
    }

    private var sourceNote: some View {
        Text("Dati da Wikidata, di pubblico dominio. Le fotografie vengono da Wikimedia Commons e restano dei rispettivi autori.")
            .font(.caption)
            .foregroundStyle(livery.onHullMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}
