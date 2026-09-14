import SwiftUI

/// La schermata che si apre per prima e che risponde a una domanda sola:
/// quanto manca, e a che cosa.
struct TodayScreen: View {
    @Environment(VoyageStore.self) private var store
    @Environment(PositionService.self) private var position
    @Environment(MarineWeatherService.self) private var weather
    @Environment(\.scenePhase) private var scenePhase

    @State private var route: [Route] = []

    /// Cambia quando cambia il punto di cui chiedere il meteo, o quando scatta l'ora.
    private var weatherKey: String {
        guard let moment = store.moment, let point = weatherPoint(moment: moment),
              weatherMoment(moment) != nil else { return "" }
        return String(format: "%.2f_%.2f_%.0f", point.latitude, point.longitude,
                      store.now.timeIntervalSince1970 / 3600)
    }

    /// Le due destinazioni raggiungibili da qui.
    enum Route: Hashable {
        case port(PortCall)
        case chart
    }

    var body: some View {
        NavigationStack(path: $route) {
            ZStack {
                store.background.ignoresSafeArea()

                if let voyage = store.voyage, store.isAwaitingDeparture,
                   case .beforeVoyage(let call)? = store.moment, let focus = store.focus {
                    // A crociera ancora lontana la schermata cambia forma: non c'è
                    // niente da misurare, quindi non si mostrano strumenti.
                    AwaitingDepartureScreen(voyage: voyage, call: call,
                                            countdown: focus.countdown, now: store.now)
                } else if let voyage = store.voyage, let moment = store.moment {
                    content(voyage: voyage, moment: moment)
                } else {
                    NoVoyageView()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .port(let call):
                    PortDetailScreen(call: call)
                case .chart:
                    ChartScreen(initialFraming: chartFraming)
                        // **Push normale, non la transizione a zoom dalla card.** La
                        // transizione a zoom porta con sé un gesto di chiusura a pinch
                        // e uno a trascinamento, e SwiftUI non espone nessuna opzione
                        // per spegnerli: il pinch per rimpicciolire la carta la
                        // chiudeva. Col push normale si torna indietro solo dal bordo
                        // sinistro o col tasto, e il pinch resta alla carta. Si perde
                        // l'animazione dalla card, e va bene così: una carta che si
                        // chiude mentre la usi è peggio di una carta che entra da destra.
                        .toolbar(.hidden, for: .navigationBar)
                        // **Niente barra delle schede sopra la carta.** Stava in basso,
                        // sopra il disegno, e il dito di sotto di un pinch per
                        // rimpicciolire ci finiva sopra: la barra di iOS 26 cambia
                        // scheda anche se ci trascini il dito, e la carta "si
                        // chiudeva" — in realtà si passava alla scheda Nave. Una carta
                        // a tutto schermo è a tutto schermo.
                        .toolbar(.hidden, for: .tabBar)
                }
            }
        }
        #if DEBUG
        .task { if DebugLaunch.open == "carta", store.voyage != nil { route = [.chart] } }
        #endif
        .onChange(of: scenePhase) { _, phase in
            // Mentre l'app era sospesa il tempo è passato lo stesso: il countdown
            // va riallineato all'adesso vero, non ripreso da dove si era fermato.
            if phase == .active {
                store.refresh()
                position.start()
            } else {
                position.stop()
            }
        }
        // La posizione si chiede quando serve davvero: in porto, dove alimenta il
        // "sei a 1,9 km dalla nave". Chiederla al primo avvio — dietro l'onboarding,
        // per giunta — significa chiederla senza che si veda a cosa serve, ed è il
        // modo migliore per farsela negare.
        .task(id: store.isInPort) {
            guard store.voyage != nil, store.isInPort else { return }
            position.requestAccess()
        }
        // Il meteo si aggiorna quando cambia il punto o passa un'ora, mai a ogni
        // ridisegno: `load` se la finestra è ancora buona non tocca la rete.
        .task(id: weatherKey) {
            guard let moment = store.moment, let point = weatherPoint(moment: moment),
                  weatherMoment(moment) != nil else { return }
            await weather.load(for: point, now: store.now)
        }
    }

    @ViewBuilder
    private func content(voyage: Voyage, moment: Voyage.Moment) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                header(voyage: voyage, moment: moment)

                ShipClockBanner(clock: voyage.clock, now: store.now)

                ClockChangeNotice(clock: voyage.clock, now: store.now)

                if case .atSea(_, let destination) = moment,
                   let estimate = ArrivalEstimate.estimate(track: store.track,
                                                           destination: destination, now: store.now),
                   estimate.isLate {
                    ArrivalDelayNotice(estimate: estimate, port: destination, clock: voyage.clock)
                }

                hero(voyage: voyage, moment: moment)

                chartCard(voyage: voyage)

                seaCard(moment: moment)

                if case .inPort = moment { AppleWeatherLink() }

                ashoreRow(voyage: voyage, moment: moment)

                tiles(voyage: voyage, moment: moment)

                nextCallRow(voyage: voyage, moment: moment)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Che mare c'è

    /// Il punto di cui chiedere il meteo: dove sei adesso in mare, il porto dove sei
    /// ormeggiato, quello dove ti imbarcherai. Sempre un posto solo — chiedere il
    /// meteo di tutta la rotta costerebbe una chiamata per scalo e non servirebbe a
    /// niente: la previsione oltre i tre giorni non è una previsione.
    private func weatherPoint(moment: Voyage.Moment) -> Coordinate? {
        switch moment {
        case .atSea(let from, let to):
            // A metà traversata il mare intorno alla nave, non quello dei porti.
            store.scheduledFix?.coordinate ?? Geo.interpolate(from: from.coordinate,
                                                              to: to.coordinate, fraction: 0.5)
        case .inPort(let call), .beforeVoyage(let call):
            call.coordinate
        case .completed:
            nil
        }
    }

    /// L'ora di cui ha senso chiedere il meteo, e come chiamarla.
    ///
    /// Prima dell'imbarco l'ora giusta non è adesso: è quando sali. E se salire è
    /// fra due mesi, non c'è nessuna previsione da dare — i modelli arrivano a tre
    /// giorni. Meglio niente che il tempo di oggi in un porto dove non sei.
    /// Dove sta la nave rispetto al mare di cui parla la scheda del meteo.
    private func mooring(_ moment: Voyage.Moment) -> SeaState.Mooring {
        switch moment {
        case .atSea: .underway
        case .inPort(let call), .beforeVoyage(let call):
            call.berth.kind == .tender ? .tender : .alongside
        case .completed: .alongside
        }
    }

    private func weatherMoment(_ moment: Voyage.Moment) -> (at: Date, title: String)? {
        switch moment {
        case .atSea:
            (store.now, String(localized: "Mare"))
        case .inPort:
            (store.now, String(localized: "In porto"))
        case .beforeVoyage(let call):
            call.arrival <= store.now.addingTimeInterval(3 * 86_400)
                ? (call.arrival, String(localized: "All'imbarco")) : nil
        case .completed:
            nil
        }
    }

    @ViewBuilder
    private func seaCard(moment: Voyage.Moment) -> some View {
        if let point = weatherPoint(moment: moment), let when = weatherMoment(moment),
           let conditions = weather.conditions(for: point, at: when.at), !conditions.isEmpty,
           // La previsione deve riguardare davvero quell'ora: se la più vicina è a
           // ore di distanza vuol dire che siamo fuori dalla finestra dei modelli.
           abs(conditions.time.timeIntervalSince(when.at)) < 3 * 3600 {
            SeaStateCard(conditions: conditions, now: store.now, title: when.title,
                         mooring: mooring(moment))
                .transition(.opacity)
        }
    }

    // MARK: Testata

    @ViewBuilder
    private func header(voyage: Voyage, moment: Voyage.Moment) -> some View {
        AdaptiveHStack(verticalAlignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(voyage.shipName)
                    .font(Type.screenTitle)
                    .tracking(Type.titleTracking)
                    .foregroundStyle(Palette.inkPrimary)
                if let day = store.today {
                    Text("Giorno \(day.number) di \(store.days.count)")
                        .font(Type.screenSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            AdaptiveSpacer()
            StatusPill(moment: moment)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Il pannello principale

    @ViewBuilder
    private func hero(voyage: Voyage, moment: Voyage.Moment) -> some View {
        switch moment {
        case .inPort(let call):
            if let focus = store.focus, case .allAboard = focus.kind {
                AllAboardHero(call: call, countdown: focus.countdown,
                              clock: voyage.clock, now: store.now, offset: store.timeOffset)
            } else {
                SimpleHero(
                    glyph: "ferry.fill", tint: Palette.ashore,
                    title: String(localized: "All aboard passato"),
                    message: String(localized: "La nave lascia \(call.name) alle \(voyage.clock.time(call.castOff))."))
            }

        case .atSea(let from, let to):
            if let focus = store.focus {
                CrossingHero(from: from, to: to, countdown: focus.countdown,
                             clock: voyage.clock, now: store.now, offset: store.timeOffset,
                             fix: position.shipFix(for: voyage, at: store.now),
                             speedUnit: store.speedUnit)
            }

        case .beforeVoyage(let call):
            if let focus = store.focus {
                BoardingHero(call: call, countdown: focus.countdown,
                             clock: voyage.clock, now: store.now, offset: store.timeOffset)
            }

        case .completed:
            SimpleHero(
                glyph: "checkmark.seal.fill", tint: Palette.action,
                title: String(localized: "Crociera conclusa"),
                message: String(localized: "\(voyage.calls.count) scali, \(voyage.nights) notti a bordo."))
        }
    }

    // MARK: Righe di contorno

    /// Quanto sei lontano dalla nave. Compare solo quando la domanda ha una risposta:
    /// sei sceso a terra, in un porto, col permesso di posizione concesso.
    @ViewBuilder
    private func ashoreRow(voyage: Voyage, moment: Voyage.Moment) -> some View {
        if let distance = position.distanceToShip(for: voyage, at: store.now) {
            InfoRow(glyph: "figure.walk", tint: Palette.underway,
                    title: String(localized: "Sei a \(Format.distance(metres: distance)) dalla nave"),
                    subtitle: String(localized: "in linea d'aria, non lungo la strada"))
        }
    }

    /// L'anteprima della carta, che porta alla carta intera.
    ///
    /// Non è un'immagine: è lo stesso disegnatore della schermata a tutto schermo,
    /// con meno dettagli. Così l'anteprima non può mai raccontare una posizione
    /// diversa da quella vera.
    @ViewBuilder
    private func chartCard(voyage: Voyage) -> some View {
        NavigationLink(value: Route.chart) {
            ChartPreviewCard(voyage: voyage,
                             fix: position.shipFix(for: voyage, at: store.now),
                             now: store.now,
                             framing: chartFraming,
                             title: seaArea(voyage: voyage))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Apri la carta"))
    }

    /// Con che inquadratura si apre la carta: **la stessa della card da cui si
    /// arriva**. Prima la card mostrava il porto da vicino e la carta si apriva a
    /// 7,5°: l'ingrandimento partiva da un'immagine e arrivava a un'altra, e si
    /// vedeva. Prima della partenza non c'è ancora una nave da inquadrare, quindi
    /// si guarda tutta la rotta.
    private var chartFraming: SeaChart.Framing {
        store.isAwaitingDeparture
            ? .wholeVoyage
            : .ship(spanDegrees: store.isInPort ? 1.4 : 7.5)
    }

    /// Dove si è, detto come lo direbbe una persona: il porto, o la meta.
    private func seaArea(voyage: Voyage) -> String {
        switch store.moment {
        case .inPort(let call): call.name
        case .atSea(_, let to): String(localized: "Verso \(to.name)")
        case .beforeVoyage(let call): call.name
        case .completed, .none: voyage.calls.last?.name ?? ""
        }
    }

    /// Due riquadri: l'ora di bordo e dove si è.
    ///
    /// Non ripetono ciò che il pannello sopra già dice. La prima versione metteva qui
    /// "Partenza 18:00" mentre il pannello lo mostrava a tre centimetri di distanza:
    /// due volte lo stesso dato è rumore, e toglie spazio a quello che manca.
    @ViewBuilder
    private func tiles(voyage: Voyage, moment: Voyage.Moment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MetricTile(label: String(localized: "Ora di bordo"),
                       value: voyage.clock.time(store.now),
                       detail: voyage.clock.offsetLabel(at: store.now),
                       spoken: voyage.clock.time(store.now))

            if let fix = position.shipFix(for: voyage, at: store.now) {
                CoordinateTile(fix: fix, now: store.now)
            }
        }
    }

    /// La riga verso il prossimo scalo. Ha la freccia perché porta davvero altrove.
    @ViewBuilder
    private func nextCallRow(voyage: Voyage, moment: Voyage.Moment) -> some View {
        if let next = upcoming(voyage: voyage, moment: moment) {
            NavigationLink(value: Route.port(next)) {
                InfoRow(glyph: "mappin.and.ellipse", tint: Palette.action,
                        title: next.name,
                        subtitle: subtitle(for: next, clock: voyage.clock)) {
                    Disclosure()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func upcoming(voyage: Voyage, moment: Voyage.Moment) -> PortCall? {
        switch moment {
        case .inPort(let call): call
        case .atSea(_, let to): to
        case .beforeVoyage(let call): call
        case .completed: nil
        }
    }

    private func subtitle(for call: PortCall, clock: ShipClock) -> String {
        var parts = [Format.window(from: call.arrival, to: call.departure, clock: clock),
                     call.berth.label]
        if let allAboard = call.allAboard {
            parts.append(String(localized: "all aboard \(clock.time(allAboard))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Un pannello semplice per gli stati in cui non c'è un countdown da mostrare.
struct SimpleHero: View {
    let glyph: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: glyph)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.inkPrimary)
            Text(message)
                .font(Type.rowDetail)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .glassSurface(cornerRadius: 30, prominence: .card, tint: tint)
        .accessibilityElement(children: .combine)
    }
}

/// La striscia che compare quando il telefono e la nave non segnano la stessa ora.
///
/// È il momento in cui l'app rischia di più: chi legge crede di stare guardando
/// l'ora del porto, e invece a bordo l'orologio dice un'altra cosa. Meglio dirlo
/// forte che lasciarlo dedurre.
struct ShipClockBanner: View {
    let clock: ShipClock
    let now: Date

    var body: some View {
        if !clock.matchesDevice(at: now) {
            let drift = clock.deviceDrift(at: now)
            let hours = abs(drift) / 3600
            let direction = drift > 0
                ? String(localized: "avanti", comment: "Il telefono rispetto alla nave")
                : String(localized: "indietro", comment: "Il telefono rispetto alla nave")

            StaleDataNotice(message: "Il telefono è \(hours) ore \(direction) rispetto all'ora di bordo. Gli orari qui sono in ora di bordo.")
        }
    }
}

#Preview("In porto") {
    TodayScreen()
        .environment(VoyageStore.preview)
        .environment(PositionService())
        .environment(NotificationScheduler())
        .environment(LiveActivityController())
        .environment(Reachability())
        .preferredColorScheme(.dark)
}

#Preview("In mare") {
    TodayScreen()
        .environment(VoyageStore.previewAtSea)
        .environment(PositionService())
        .environment(NotificationScheduler())
        .environment(LiveActivityController())
        .environment(Reachability())
        .preferredColorScheme(.dark)
}
