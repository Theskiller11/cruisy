import SwiftUI

/// La scheda della nave: la nave disegnata, le carte di bordo, dove si trova.
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
    @Environment(PositionService.self) private var position

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
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func content(voyage: Voyage) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                // La copertina è la nave, disegnata nei colori della livrea sul mare
                // dell'ora di bordo. Prima in cima c'era la carta della rotta, che è
                // anche su Oggi: qui si guarda la nave.
                SeaScene(hour: store.shipHour, setting: store.isInPort ? .port : .openSea, shipScale: 1)
                    .frame(height: 230)
                    .padding(.horizontal, -16)
                    // Il nome sale sull'acqua, come il biglietto su Oggi: sotto le
                    // onde la scena è già scafo, e lasciarla intera apriva un vuoto.
                    .padding(.bottom, -52)

                Masthead(record?.name ?? voyage.shipName, detail: identity)
                    .padding(.horizontal, 6)

                papers(voyage: voyage)

                if record == nil {
                    missingShip(name: voyage.shipName)
                }

                whereabouts(voyage: voyage)

                if let photo = photos.photo {
                    ShipPhotoCard(photo: photo)
                }

                sourceNote
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .shrinksTabBar()
        .task(id: "\(record?.imageFile ?? "")|\(reachability.isExpensive)") {
            if let record {
                await photos.load(record, allowsDownload: PhotoDownloadPolicy.allows(isMetered: reachability.isExpensive))
            }
        }
    }

    /// La riga sotto il nome: chi la gestisce, la bandiera, da quando naviga.
    private var identity: String? {
        guard let record else { return nil }
        var parts: [String] = []
        if !record.operatorName.isEmpty { parts.append(record.operatorName) }
        if !record.flag.isEmpty { parts.append(record.flag) }
        if record.year > 0 { parts.append(String(localized: "dal \(String(record.year))")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Le carte di bordo

    /// Le misure come campi del biglietto, la livrea come i suoi colori; nella
    /// matrice gli identificativi, in carattere tecnico. Il nome non si ripete: è
    /// già scritto grande sopra.
    @ViewBuilder
    private func papers(voyage: Voyage) -> some View {
        let fields = paperFields
        let imo = record?.imo.isEmpty == false ? record?.imo : voyage.imo
        let mmsi = record?.mmsi.isEmpty == false ? record?.mmsi : voyage.mmsi
        Ticket {
            VStack(alignment: .leading, spacing: 14) {
                Text("Carte di bordo").ticketEyebrow(livery.signalInk)
                if !fields.isEmpty { TicketMatrix(fields: fields, columns: 3) }
                liveryField
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 16)
        } stub: {
            HStack(alignment: .top, spacing: 14) {
                technical("IMO", imo)
                technical("MMSI", mmsi)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var paperFields: [TicketField] {
        guard let record else { return [] }
        var fields: [TicketField] = []
        if record.tonnage > 0 {
            fields.append(TicketField(label: String(localized: "Stazza"), value: Format.tonnage(record.tonnage)))
        }
        if record.length > 0 {
            fields.append(TicketField(label: String(localized: "Lunghezza"), value: "\(Int(record.length)) m"))
        }
        if record.beam > 0 {
            fields.append(TicketField(label: String(localized: "Larghezza"), value: "\(Int(record.beam)) m"))
        }
        return fields
    }

    /// La livrea come la si vede: i suoi tre colori, il nome, e dove si cambia.
    private var liveryField: some View {
        let fromCompany = preferences.livery == .company && livery != .cruisy
        return HStack(alignment: .center, spacing: 12) {
            HStack(spacing: -4) {
                ForEach(Array([livery.hull, livery.paper, livery.signal].enumerated()), id: \.offset) { _, colour in
                    Circle().fill(colour)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(livery.perforation, lineWidth: 1))
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Livrea: \(livery.name)")
                    .font(TicketType.rowTitle)
                    .foregroundStyle(livery.ink)
                // Due `Text` e non un `Text` con la condizione dentro: due letterali in un
                // ternario diventano una `String`, e una `String` non si traduce.
                (fromCompany ? Text("Colori ispirati alla compagnia. Si cambia nelle Impostazioni.")
                             : Text("La livrea di Cruisy. Si cambia nelle Impostazioni."))
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.field)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func technical(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label).ticketFieldLabel(livery.field)
            Text(verbatim: value ?? "—")
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundStyle(value == nil ? livery.field : livery.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Dove si trova

    /// La nave sulla carta: dov'è adesso in crociera, la rotta intera prima e dopo.
    @ViewBuilder
    private func whereabouts(voyage: Voyage) -> some View {
        let underway = !store.isAwaitingDeparture && store.moment != .completed
        let fix = underway ? position.shipFix(for: voyage, at: store.now) : nil
        VStack(alignment: .leading, spacing: 0) {
            SeaChart(voyage: voyage, fix: fix, now: store.now,
                     framing: fix != nil ? .ship(spanDegrees: 7.5) : .wholeVoyage,
                     showsPortNames: fix == nil, showsGraticule: true, showsShip: fix != nil, padding: 22)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(6)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                (fix != nil ? Text("Dove si trova") : Text("La rotta")).ticketFieldLabel(livery.field)
                Spacer(minLength: 8)
                Text(whereLine(voyage: voyage))
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .paperCard()
        .accessibilityElement(children: .combine)
    }

    private func whereLine(voyage: Voyage) -> String {
        switch store.moment {
        case .inPort(let call): String(localized: "In porto a \(call.name)")
        case .atSea(_, let to): String(localized: "Verso \(to.name)")
        case .beforeVoyage, .completed, .none:
            String(localized: "\(voyage.nights) notti · \(voyage.intermediateCalls.count) scali")
        }
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
                // Una riga come quelle dei suggerimenti, non un pulsante a tutta
                // larghezza: la scheda è un di più, e non deve sembrare un errore.
                Button {
                    Task { await lookup.search(name) }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Non è nell'elenco dell'app")
                                .font(TicketType.rowTitle)
                                .foregroundStyle(livery.ink)
                            Text("Cerca nave su Wikidata")
                                .font(TicketType.rowDetail)
                                .foregroundStyle(livery.tint)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(livery.tint)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paperCard()
    }

    @ViewBuilder
    private func retry(name: String) -> some View {
        Button("Riprova") { Task { await lookup.search(name) } }
            .font(TicketType.rowTitle)
            .tint(livery.tint)
    }

    private var sourceNote: some View {
        Text("Dati da Wikidata, di pubblico dominio. Le fotografie vengono da Wikimedia Commons e restano dei rispettivi autori.")
            .font(.caption)
            .foregroundStyle(livery.onHullMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}
