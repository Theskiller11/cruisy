import SwiftUI
import UniformTypeIdentifiers

/// Le impostazioni: condivisione della crociera, unità, avvisi, fonti.
struct SettingsSheet: View {
    @Environment(VoyageStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(PositionService.self) private var position
    @Environment(\.dismiss) private var dismiss

    @State private var exported: URL?
    @State private var isOpeningFile = false
    @State private var incoming: Voyage?
    @State private var problem: String?
    @State private var proxy = UserDefaults.standard.string(forKey: "cruisy.proxy") ?? ""
    @State private var learnedShips = ShipOverlay.count
    @AppStorage(PhotoDownloadPolicy.meteredKey) private var photosOnMetered = false

    var body: some View {
        NavigationStack {
            Form {
                sharingSection
                liveActivitySection
                trackingSection
                unitsSection
                weatherSection
                photosSection
                shipsSection
                aboutSection
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
            .fileImporter(isPresented: $isOpeningFile,
                          allowedContentTypes: [.cruisyVoyage, .json]) { result in
                guard case .success(let url) = result else { return }
                do { incoming = try VoyageFile.read(from: url) }
                catch { problem = String(localized: "Questo file non contiene una crociera che riesco a leggere.") }
            }
            .alert("Sostituire la crociera?", isPresented: Binding(
                get: { incoming != nil }, set: { if !$0 { incoming = nil } })) {
                Button("Annulla", role: .cancel) { incoming = nil }
                Button("Sostituisci", role: .destructive) {
                    if let incoming { store.replace(with: incoming) }
                    incoming = nil
                    dismiss()
                }
            } message: {
                // Mai sovrascrivere in silenzio: l'itinerario attuale può contenere
                // correzioni fatte a bordo che non stanno da nessun'altra parte.
                if let incoming {
                    Text("Prenderai «\(incoming.shipName)» con \(incoming.calls.count) scali. La crociera che hai adesso, e le correzioni che le hai fatto, andranno perse.")
                }
            }
            .alert("Non ci siamo", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("Va bene", role: .cancel) { problem = nil }
            } message: {
                if let problem { Text(problem) }
            }
        }
    }

    // MARK: Condivisione

    @ViewBuilder
    private var sharingSection: some View {
        Section {
            if let voyage = store.voyage {
                ShareLink(item: exportURL(for: voyage) ?? URL(fileURLWithPath: "/dev/null"),
                          preview: SharePreview(voyage.shipName,
                                                image: Image(systemName: "ferry.fill"))) {
                    Label("Condividi la crociera", systemImage: "square.and.arrow.up")
                }
                .disabled(exportURL(for: voyage) == nil)
            }

            Button {
                isOpeningFile = true
            } label: {
                Label("Apri una crociera da file", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("La tua crociera")
        } footer: {
            Text("Salvala come file e mandala a chi viaggia con te, o al tuo iPad: la apre e ce l'ha. Nessun account, nessun nostro server. Su una nave conviene anche di più della sincronizzazione automatica, perché AirDrop funziona senza rete.")
        }
    }

    /// Scrive il file una volta sola per sessione: rifarlo a ogni ridisegno
    /// riscriverebbe su disco a ogni battito dell'interfaccia.
    private func exportURL(for voyage: Voyage) -> URL? {
        if let exported { return exported }
        let url = try? VoyageFile.export(voyage)
        Task { @MainActor in exported = url }
        return url
    }

    // MARK: Il resto

    /// Il countdown sulla schermata di blocco.
    ///
    /// Sta qui e non più nella schermata Oggi: era una riga in mezzo ai dati, e
    /// un'impostazione in mezzo ai dati è rumore quando non ti serve e introvabile
    /// quando ti serve.
    private var liveActivitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.wantsLiveActivity },
                set: { preferences.wantsLiveActivity = $0 })) {
                    Text("Countdown sulla schermata di blocco")
                }
            LiveActivitySetting()
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
        } header: {
            Text("Schermata di blocco")
        } footer: {
            Text("Si accende in porto nelle ultime otto ore prima dell'all aboard, e in mare nell'ultima ora e mezza prima dell'attracco.")
        }
    }

    /// La registrazione della rotta.
    ///
    /// Il permesso permanente non si chiede all'apertura delle impostazioni: si
    /// chiede **quando accendi l'interruttore**, cioè nel momento in cui si vede a
    /// cosa serve. Chiederlo prima è il modo migliore per farselo negare, e iOS lo
    /// domanda una volta sola.
    @ViewBuilder
    private var trackingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.wantsTracking },
                set: { wanted in
                    preferences.wantsTracking = wanted
                    if wanted { position.requestAlwaysAccess() }
                })) {
                    Text("Registra la rotta percorsa")
                }

            if preferences.wantsTracking, !position.canTrackInBackground {
                // Distinguere "non l'hai ancora dato" da "l'hai negato": la prima si
                // risolve qui, la seconda solo in Impostazioni di sistema.
                Label {
                    Text(position.isDenied
                         ? "Hai negato la posizione. Serve «Sempre» in Impostazioni › Cruisy › Posizione."
                         : "Manca il permesso «Sempre». Senza, la rotta si registra solo mentre l'app è aperta.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.ashore)
                }
                .font(Type.rowDetail)
            }

            if !store.recorder.track.isEmpty {
                LabeledContent("Punti registrati", value: "\(store.recorder.track.points.count)")
                LabeledContent("Miglia vere",
                               value: Format.nauticalMiles(store.recorder.track.nauticalMiles))
            }
        } header: {
            Text("Rotta")
        } footer: {
            Text("Segna dove passa la nave anche col telefono in tasca, per disegnare la traversata nel diario e contare le miglia vere invece di quelle in linea retta fra i porti. Consuma batteria e si spegne da sola quando sbarchi.")
        }
    }

    private var unitsSection: some View {
        Section("Unità") {
            Picker("Velocità", selection: Binding(
                get: { preferences.speedUnit },
                set: { preferences.speedUnit = $0 })) {
                    ForEach(SpeedUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                }
        }
    }

    /// Il proxy è facoltativo e sta in fondo: chi non sa cosa sia non deve
    /// incontrarlo. Chi ne ha uno in casa risparmia chiamate al piano gratuito di
    /// Open-Meteo, che ha un tetto giornaliero condiviso da tutti.
    private var photosSection: some View {
        Section {
            Toggle("Scarica le foto anche su rete a consumo", isOn: $photosOnMetered)
        } header: {
            Text("Foto")
        } footer: {
            Text("Le foto di navi e porti arrivano da Wikimedia Commons e Wikipedia. Su rete cellulare, hotspot o Risparmio dati si scaricano solo se lo permetti; quelle già viste restano sempre. Il Wi-Fi della nave per iPhone è un Wi-Fi normale, anche se lo paghi: per risparmiare lì, attiva Risparmio dati su quella rete.")
        }
    }

    private var weatherSection: some View {
        Section {
            TextField("http://…", text: $proxy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onChange(of: proxy) { _, new in
                    UserDefaults.standard.set(new, forKey: "cruisy.proxy")
                }
        } header: {
            Text("Proxy meteo (facoltativo)")
        } footer: {
            Text("Vuoto: Cruisy chiede il meteo direttamente a Open-Meteo. Se hai un proxy con cache, mettine qui l'indirizzo.")
        }
    }

    /// Le navi cercate su Wikidata dopo l'installazione.
    ///
    /// C'è perché un'app che impara deve poter anche dimenticare: se una scheda è
    /// arrivata sbagliata — nome ambiguo, voce di Wikidata incompleta — deve
    /// esistere il modo di toglierla senza reinstallare tutto.
    @ViewBuilder
    private var shipsSection: some View {
        if learnedShips > 0 {
            Section {
                LabeledContent("Navi imparate", value: "\(learnedShips)")
                Button("Dimentica le navi cercate", role: .destructive) {
                    ShipOverlay.forgetAll()
                    ShipDirectory.shared.loadLearned()
                    learnedShips = 0
                }
            } footer: {
                Text("L'elenco che viaggia dentro l'app resta intatto: si tolgono solo le schede scaricate da Wikidata a bordo.")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink("Come funziona Cruisy") { DisclaimerSheet {} }
            LabeledContent("Coste", value: "Natural Earth")
            LabeledContent("Porti", value: "World Port Index · UN/LOCODE")
            LabeledContent("Navi", value: "Wikidata")
            LabeledContent("Meteo e onde", value: "Open-Meteo · CC BY 4.0")
        } header: {
            Text("Dati")
        } footer: {
            Text("Coste, porti e dati delle navi sono di pubblico dominio e viaggiano dentro l'app: la carta si disegna anche senza rete. Il meteo arriva da Open-Meteo; le fotografie delle navi da Wikimedia Commons, con il credito del loro autore.")
        }
    }
}
