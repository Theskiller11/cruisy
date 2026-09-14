import SwiftUI

/// Le tre schede di Cruisy.
///
/// `TabView` nativa e non la pillola di vetro disegnata a mano del brief: su iOS 26
/// la barra è già Liquid Glass, si rimpicciolisce da sola allo scorrimento, rispetta
/// l'inset dell'indicatore Home e porta con sé l'accessibilità. Rifarla a mano
/// significherebbe rifare peggio anche quelle cose, comprese le etichette a 9,5 px
/// che l'audit ha bocciato.
///
/// Tre e non cinque: "Nave" e "Logbook" non servono in banchina, e il deck plan di
/// una nave reale è materiale di terzi.
struct RootTabView: View {
    @Environment(LiveActivityController.self) private var activities
    @Environment(VoyageStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(PositionService.self) private var position
    @State private var selection: Section = .today
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

    enum Section: Hashable {
        case today, itinerary, ship, logbook
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: .today) {
                TodayScreen()
            } label: {
                // Etichette che dicono che cosa c'è dentro, non categorie ombrello.
                Label("Oggi", systemImage: "sun.horizon")
            }

            Tab(value: .itinerary) {
                ItineraryScreen()
            } label: {
                Label("Itinerario", systemImage: "list.bullet.indent")
            }

            Tab(value: .ship) {
                ShipScreen()
            } label: {
                Label("Nave", systemImage: "ferry")
            }

            Tab(value: .logbook) {
                LogbookScreen()
            } label: {
                Label("Diario", systemImage: "book.closed")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(store.accent)
        // Un file .cruisy ricevuto per AirDrop, messaggio o email apre qui.
        .onOpenURL { url in
            do { incoming = try VoyageFile.read(from: url) }
            catch { openProblem = true }
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
            if let incoming {
                Text(store.voyage == nil
                     ? "«\(incoming.shipName)», \(incoming.calls.count) scali."
                     : "Prenderai «\(incoming.shipName)» con \(incoming.calls.count) scali. La crociera che hai adesso, e le correzioni che le hai fatto, andranno perse.")
            }
        }
        .alert("Non riesco ad aprirlo", isPresented: $openProblem) {
            Button("Va bene", role: .cancel) { }
        } message: {
            Text("Questo file non contiene una crociera che riesco a leggere.")
        }
        .sheet(isPresented: $showsDisclaimer) {
            OnboardingFlow { preferences.hasSeenDisclaimer = true }
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
        #endif
        #if DEBUG
        // `-liveActivity` accende l'attività all'avvio. Esiste perché per vederla
        // bisogna altrimenti trovare l'interruttore, e la Dynamic Island espansa
        // vuole una pressione lunga: senza questo, l'unico modo di verificarla è
        // chiederlo a qualcuno con un telefono in mano — che è come ci si accorge
        // di un renderer caduto solo dopo averlo consegnato.
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
            // `-tab carta|itinerario` apre direttamente una scheda, per pilotare
            // la verifica dal simulatore senza toccare lo schermo.
            switch ProcessInfo.processInfo.arguments.last(where: { ["itinerario","oggi","nave","diario"].contains($0) }) {
            case "itinerario": selection = .itinerary
            case "nave": selection = .ship
            case "diario": selection = .logbook
            default: break
            }
            #endif
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
        .environment(NotificationScheduler())
        .preferredColorScheme(.dark)
}
