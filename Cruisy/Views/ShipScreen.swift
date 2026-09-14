import SwiftUI

/// La scheda della nave.
///
/// Si riempie da sola dal nome: i dati vengono da Wikidata, che è **CC0** — stazza,
/// lunghezza, numero IMO, anno di consegna sono fatti, e i fatti non appartengono a
/// nessuno. Il piano dei ponti invece resta fuori: quello è materiale della
/// compagnia, ed è la ragione per cui questa schermata esiste in questa forma e non
/// in quella del brief.
struct ShipScreen: View {
    @Environment(VoyageStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photos = ShipPhotoService()
    @Environment(Reachability.self) private var reachability
    @Environment(ShipLookupService.self) private var lookup

    private var record: ShipRecord? {
        store.voyage.flatMap { ShipDirectory.shared.lookup($0.shipName) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                store.background.ignoresSafeArea()
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
            VStack(spacing: 12) {
                photo(voyage: voyage)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record?.name ?? voyage.shipName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.inkPrimary)
                    if let operatorName = record?.operatorName, !operatorName.isEmpty {
                        Text(operatorName)
                            .font(Type.screenSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let record {
                    measurements(record)
                }

                identifiers(voyage: voyage)

                if record == nil, let voyage = store.voyage {
                    missingShip(name: voyage.shipName)
                }

                sourceNote
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
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
        VStack(alignment: .trailing, spacing: 6) {
            photoFrame(voyage: voyage)
            if let photo = photos.photo, typeSize.isAccessibilitySize {
                creditLabel(photo.credit)
            }
        }
    }

    @ViewBuilder
    private func photoFrame(voyage: Voyage) -> some View {
        // La foto sta in un **overlay**, non dentro allo ZStack: riempiendo a
        // `.fill` l'immagine è più larga del riquadro, e da figlia diretta imponeva
        // quella larghezza a tutta la colonna — ecco perché il nome della nave e i
        // crediti finivano oltre il bordo sinistro dello schermo. Un overlay non
        // può cambiare la misura di ciò che riveste: `clipShape` nasconde
        // l'eccedenza, ma è la struttura che deve impedirla.
        Rectangle()
            .fill(Palette.seaHigh)
            .overlay {
                if let photo = photos.photo {
                    Image(uiImage: photo.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .overlay {
                if photos.photo == nil {
                    // Senza foto non si lascia un buco: si disegna la rotta, che è
                    // un contenuto vero e sempre disponibile.
                    ZStack {
                        SeaChart(voyage: voyage, fix: nil, now: store.now,
                                 framing: .wholeVoyage, showsPortNames: false,
                                 showsGraticule: true, showsShip: false, padding: 26)
                        if photos.isLoading {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Palette.hairline, lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) {
            // Il credito sta **sulla** foto: è la condizione con cui l'autore la
            // mette a disposizione, non una nota a piè di pagina. Ai corpi
            // accessibili però la pastiglia coprirebbe l'immagine, quindi lì
            // scende sotto — visibile lo stesso, senza nascondere quello che
            // sta accreditando.
            if let photo = photos.photo, !typeSize.isAccessibilitySize {
                creditLabel(photo.credit)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.abyss.opacity(0.7)))
                    .padding(8)
            }
        }
        .padding(.top, 8)
    }

    /// La riga di credito. Mai sotto gli 11pt e mai a dimensione fissa: è l'unica
    /// cosa che la licenza **obbliga** a mostrare, e deve restare leggibile a
    /// qualunque corpo di testo.
    private func creditLabel(_ credit: String) -> some View {
        Text(credit)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Palette.inkSecondary)
            .lineLimit(3)
            .multilineTextAlignment(.trailing)
    }

    // MARK: I numeri

    @ViewBuilder
    private func measurements(_ record: ShipRecord) -> some View {
        let metrics: [Metric] = [
            record.tonnage > 0
                ? Metric(value: Format.tonnage(record.tonnage), label: String(localized: "Stazza")) : nil,
            record.length > 0
                ? Metric(value: "\(Int(record.length)) m", label: String(localized: "Lunghezza")) : nil,
            record.beam > 0
                ? Metric(value: "\(Int(record.beam)) m", label: String(localized: "Larghezza")) : nil,
            record.year > 0
                ? Metric(value: "\(record.year)", label: String(localized: "In servizio")) : nil,
            record.flag.isEmpty
                ? nil : Metric(value: record.flag, label: String(localized: "Bandiera")),
        ].compactMap(\.self)

        if !metrics.isEmpty {
            MetricRow(metrics: metrics, columns: 3)
                .padding(16)
                .glassSurface(cornerRadius: 24, prominence: .card)
        }
    }

    @ViewBuilder
    private func identifiers(voyage: Voyage) -> some View {
        let imo = record?.imo.isEmpty == false ? record?.imo : voyage.imo
        let mmsi = record?.mmsi.isEmpty == false ? record?.mmsi : voyage.mmsi

        if imo != nil || mmsi != nil {
            VStack(spacing: 10) {
                if let imo { row(label: "IMO", value: imo) }
                if let mmsi { row(label: "MMSI", value: mmsi) }
            }
            .padding(16)
            .glassSurface(cornerRadius: 20, prominence: .chip)
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).eyebrow()
            Spacer(minLength: 12)
            Text(value)
                .font(Type.technical)
                .foregroundStyle(Palette.inkPrimary)
        }
        .accessibilityElement(children: .combine)
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
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            case .notFound:
                Label("Su Wikidata non c'è nessuna nave con questo nome. Controlla come è scritto: conta la grafia, non le maiuscole.",
                      systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                retry(name: name)
            case .failed(let reason):
                Label("Non sono riuscito a chiedere a Wikidata: \(reason)",
                      systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                retry(name: name)
            default:
                Text("Questa nave non è nell'elenco che viaggia dentro l'app. I countdown funzionano lo stesso: la scheda è un di più.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                Button {
                    Task { await lookup.search(name) }
                } label: {
                    Label("Cercala su Wikidata", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                        // Scuro, non bianco: bianco su questo azzurro sta a 1,5:1, e
                        // `borderedProminent` lo mette bianco da sé. Scuro sta a 12:1.
                        .foregroundStyle(Palette.abyss)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassSurface(cornerRadius: 22, prominence: .card)
    }

    @ViewBuilder
    private func retry(name: String) -> some View {
        Button("Riprova") { Task { await lookup.search(name) } }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.action)
    }

    private var sourceNote: some View {
        Text("Dati da Wikidata, di pubblico dominio. Le fotografie vengono da Wikimedia Commons e restano dei rispettivi autori.")
            .font(.caption2)
            .foregroundStyle(Palette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}
