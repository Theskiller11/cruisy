import SwiftUI

/// Le quattro schede di Cruisy.
///
/// `TabView` nativa per il contenuto — tiene lo stato di ogni scheda — ma con la
/// barra nostra, `CruisyTabBar`: quella di sistema, scorrendo, si riduceva a una
/// sola icona. La nostra si rimpicciolisce e tiene tutte e quattro le voci.
///
/// Qui si decide anche la **livrea**: dalla scelta nelle Impostazioni e dalla
/// compagnia della nave, e da qui scende nell'ambiente di ogni schermata.
struct RootTabView: View {
    @Environment(LiveActivityController.self) private var activities
    @Environment(VoyageStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(PositionService.self) private var position
    @State private var selection: Section = .today
    @State private var tabBar = TabBarState()
    @State private var showsDisclaimer = false
    /// Una crociera arrivata da un file, in attesa di conferma.
    @State private var incoming: Voyage?
    @State private var openProblem = false
    @Environment(\.scenePhase) private var scenePhase

    /// Cambia solo quando cambia qualcosa che riguarda la registrazione, così il
    /// `task` non riparte a ogni battito dei trenta secondi.
    private var trackingKey: String {
        "\(preferences.wantsTracking)-\(store.voyage?.id.uuidString ?? "-")-\(store.moment == .completed)-\(position.canTrackInBackground)"
    }

    private var livery: Livery {
        #if DEBUG
        if let forced = DebugLaunch.livery { return forced }
        #endif
        return Livery.resolve(preferences.livery, operatorName: store.shipRecord?.operatorName)
    }

    enum Section: Hashable {
        case today, itinerary, ship, logbook
    }

    // Etichette che dicono che cosa c'è dentro, non categorie ombrello.
    private static let tabs: [CruisyTabBar<Section>.Item] = [
        .init(section: .today, title: "Oggi", symbol: "sun.horizon"),
        .init(section: .itinerary, title: "Itinerario", symbol: "list.bullet.indent"),
        .init(section: .ship, title: "Nave", symbol: "ferry"),
        .init(section: .logbook, title: "Diario", symbol: "book.closed"),
    ]

    var body: some View {
        TabView(selection: $selection) {
            Tab("Oggi", systemImage: "sun.horizon", value: .today) {
                TodayScreen().cruisyTab(tabBar)
            }
            Tab("Itinerario", systemImage: "list.bullet.indent", value: .itinerary) {
                ItineraryScreen().cruisyTab(tabBar)
            }
            Tab("Nave", systemImage: "ferry", value: .ship) {
                ShipScreen().cruisyTab(tabBar)
            }
            Tab("Diario", systemImage: "book.closed", value: .logbook) {
                LogbookScreen().cruisyTab(tabBar)
            }
        }
        .overlay(alignment: .bottom) {
            if !tabBar.isHidden {
                CruisyTabBar(selection: $selection, items: Self.tabs, compact: tabBar.isCompact)
                    .padding(.bottom, -6)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tabBar.isHidden)
        // Cambiando scheda la barra si riapre: la nuova schermata parte dalla
        // cima, e una barra stretta sopra una pagina mai scorsa non ha motivo.
        .onChange(of: selection) { tabBar.expand() }
        .environment(tabBar)
        .tint(livery.tabTint)
        // Senza questa la barra di stato prendeva le scritte scure sullo scafo scuro:
        // la barra di sistema è nascosta, ma è ancora lei a decidere il suo colore.
        .toolbarColorScheme(.dark, for: .tabBar)
        .environment(\.livery, livery)
        // Qui arrivano due cose diverse: il tocco su widget e Live Activity
        // (`cruisy://today`) e un file .cruisy ricevuto per AirDrop, messaggio o
        // email. Solo il secondo è una crociera da leggere: vedi `IncomingURL`.
        .onOpenURL { url in
            switch IncomingURL(url) {
            case .today:
                selection = .today
            case .voyageFile(let file):
                do { incoming = try VoyageFile.read(from: file) }
                catch { openProblem = true }
            case .unknown:
                break
            }
        }
        .alert("Aprire questa crociera?", isPresented: Binding(
            get: { incoming != nil }, set: { if !$0 { incoming = nil } })) {
            Button("Annulla", role: .cancel) { incoming = nil }
            Button(store.voyage == nil ? "Apri" : "Sostituisci",
                   role: store.voyage == nil ? nil : .destructive) {
                if let incoming { store.replace(with: incoming) }
                incoming = nil
                selection = .today
            }
        } message: {
            // Mai sovrascrivere in silenzio: la crociera che c'è può contenere
            // correzioni fatte a bordo che non stanno da nessun'altra parte.
            // Due `Text`, non un `Text` col ternario dentro: due letterali in un
            // ternario diventano una `String`, e una `String` non si traduce.
            if let incoming {
                if store.voyage == nil {
                    Text("«\(incoming.shipName)», \(incoming.calls.count) scali.")
                } else {
                    Text("Prenderai «\(incoming.shipName)» con \(incoming.calls.count) scali. La crociera che hai adesso, e le correzioni che le hai fatto, andranno perse.")
                }
            }
        }
        .alert("Non riesco ad aprirlo", isPresented: $openProblem) {
            Button("Va bene", role: .cancel) { }
        } message: {
            Text("Questo file non contiene una crociera che riesco a leggere.")
        }
        .sheet(isPresented: $showsDisclaimer) {
            OnboardingFlow { preferences.hasSeenDisclaimer = true }
                .environment(\.livery, livery)
        }
        // La registrazione della rotta segue la preferenza **e** lo stato della
        // crociera: si spegne da sola quando sbarchi. Una crociera finita che
        // continua a tenere il GPS acceso è la ragione per cui la gente disinstalla.
        .task(id: trackingKey) {
            let sailing = store.voyage != nil && store.moment != .completed
            position.setTracking(preferences.wantsTracking && sailing) { fix in
                store.record(fix: Coordinate(latitude: fix.coordinate.latitude,
                                             longitude: fix.coordinate.longitude),
                             at: fix.timestamp)
            }
        }
        // Andando in secondo piano si scrive subito: se no gli ultimi punti — fino
        // a venti, cioè quasi un'ora di navigazione — se ne andrebbero al riavvio.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.recorder.persist() }
        }
        // Sta qui e non nella riga dell'interruttore, che vive solo finché la
        // schermata Oggi è a video: l'attività va chiusa anche se sei sulla Carta.
        // `store.now` avanza ogni trenta secondi, che è la finezza che serve.
        .task(id: store.now) {
            await activities.reconcile(focus: store.focus, at: store.now)

            // La preferenza chiesta nell'onboarding deve avere un effetto, se no è
            // una domanda a vuoto: quando la finestra si apre l'attività si accende
            // da sé. Spegnerla a mano la spegne e basta — `wantsLiveActivity` resta
            // vero, ma `reconcile` non la riaccende finché il traguardo è lo stesso.
            guard preferences.wantsLiveActivity, !activities.isRunning,
                  let voyage = store.voyage, let focus = store.focus else { return }
            let atSea = if case .arrival = focus.kind { true } else { false }
            _ = activities.start(voyage: voyage, call: focus.port, countdown: focus.countdown,
                                 at: store.now, kind: atSea ? .arrival : .allAboard)
        }
        #if DEBUG
        // `-tab diario` apre l'app su una scheda precisa.
        //
        // Esiste perché su questo Mac **non c'è `Simulator.app`** — questo Xcode non
        // la installa — quindi si può pilotare solo il simulatore headless con
        // `simctl`, che sa avviare e fotografare ma non toccare. Senza questo, le
        // schermate diverse da Oggi non si possono verificare a schermo per niente.
        //
        // `-open` apre una schermata dentro la scheda giusta: vedi `DebugLaunch`.
        .task {
            switch DebugLaunch.tab ?? DebugLaunch.tabForOpen {
            case "oggi", "today": selection = .today
            case "itinerario", "itinerary": selection = .itinerary
            case "nave", "ship": selection = .ship
            case "diario", "logbook": selection = .logbook
            default: break
            }
        }
        // `-liveActivity` accende l'attività all'avvio. Esiste perché per vederla
        // bisogna altrimenti trovare l'interruttore, e la Dynamic Island espansa
        // vuole una pressione lunga: senza questo, l'unico modo di verificarla è
        // chiederlo a qualcuno con un telefono in mano.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-liveActivity"),
                  let voyage = store.voyage, let focus = store.focus else { return }
            let atSea = if case .arrival = focus.kind { true } else { false }
            _ = activities.start(voyage: voyage, call: focus.port, countdown: focus.countdown,
                                 at: store.now, kind: atSea ? .arrival : .allAboard,
                                 milesRemaining: nil)
        }
        #endif
        .task {
            #if DEBUG
            // Due fogli che si presentano insieme non ne mostrano nessuno: i flag di
            // prova che aprono altro devono saltare l'onboarding.
            let skipping = ProcessInfo.processInfo.arguments.contains("-importDemo")
                || ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
            showsDisclaimer = (!preferences.hasSeenDisclaimer && !skipping)
                || DebugLaunch.open == "onboarding"
            #else
            showsDisclaimer = !preferences.hasSeenDisclaimer
            #endif
            await notifications.refreshAuthorization()
            await notifications.reschedule(for: store.voyage)
        }
        // Un solo posto in cui riprogrammare gli avvisi: qualunque schermata cambi
        // la crociera, le notifiche si riscrivono di conseguenza. Sparpagliare questa
        // chiamata vorrebbe dire, prima o poi, dimenticarla da qualche parte.
        .onChange(of: store.voyage) { _, voyage in
            Task { await notifications.reschedule(for: voyage) }
        }
    }
}

#Preview {
    RootTabView()
        .environment(VoyageStore.preview)
        .environment(Preferences.ephemeral)
        .environment(PositionService())
        .environment(NotificationScheduler())
        .environment(LiveActivityController())
        .environment(Reachability())
        .environment(MarineWeatherService())
        .environment(ShipLookupService())
}

private extension View {
    /// Il contenuto di una scheda: senza la barra di sistema, e con in fondo lo
    /// spazio della nostra, così l'ultima card si può scorrere fin sopra di lei.
    func cruisyTab(_ bar: TabBarState) -> some View {
        self
            .toolbarVisibility(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bar.isHidden ? 0 : TabBarMetrics.height - 6)
            }
    }
}
