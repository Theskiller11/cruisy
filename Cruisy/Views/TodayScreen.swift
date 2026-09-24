import SwiftUI

/// La schermata che si apre per prima e che risponde a una domanda sola:
/// quanto manca, e a che cosa.
///
/// Sullo scafo c'è il nome della nave; sotto, la pila dei biglietti: quello di
/// oggi davanti, il prossimo scalo che si intravede dietro. In giorno di mare, sopra
/// la pila c'è il cielo di bordo con le onde che si muovono.
struct TodayScreen: View {
    @Environment(VoyageStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(PositionService.self) private var position
    @Environment(MarineWeatherService.self) private var weather
    @Environment(Reachability.self) private var reachability
    @Environment(\.livery) private var livery
    @Environment(\.scenePhase) private var scenePhase

    @State private var route: [Route] = []
    @State private var photos = ShipPhotoService()

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
                livery.hull.ignoresSafeArea()
                if let voyage = store.voyage, let moment = store.moment {
                    content(voyage: voyage, moment: moment)
                } else {
                    NoVoyageView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // Le barre sullo scafo restano scure in entrambe le modalità.
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                        // sinistro o col tasto, e il pinch resta alla carta.
                        .toolbar(.hidden, for: .navigationBar)
                        // **Niente barra delle schede sopra la carta.** Il dito di
                        // sotto di un pinch ci finiva sopra e cambiava scheda.
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
        // «sei a 1,9 km dalla nave». Chiederla al primo avvio — dietro l'onboarding,
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
        // La foto della nave, solo prima della crociera: è il momento in cui la si
        // guarda, e in cui non c'è ancora una posizione da mostrare al suo posto.
        .task(id: "\(store.shipRecord?.imageFile ?? "")|\(reachability.isExpensive)|\(store.isAwaitingDeparture)") {
            guard store.isAwaitingDeparture, let record = store.shipRecord else { return }
            await photos.load(record, allowsDownload: PhotoDownloadPolicy.allows(isMetered: reachability.isExpensive))
        }
    }

    // MARK: La pagina

    private var isAtSea: Bool {
        if case .atSea = store.moment { return true }
        return false
    }

    /// Quanto il biglietto entra nell'acqua della scena, in giorno di mare.
    private let ticketDraft: CGFloat = 54

    @ViewBuilder
    private func content(voyage: Voyage, moment: Voyage.Moment) -> some View {
        ScrollView {
            // Una sola colonna, con i pezzi condizionali direttamente dentro: un
            // gruppo vuoto in una `VStack` con spaziatura è comunque un figlio, e
            // al primo giro lasciava un vuoto di quaranta punti sotto il biglietto.
            VStack(spacing: 12) {
                Masthead(voyage.shipName, detail: dayLine(voyage: voyage))
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, isAtSea || store.isInPort ? 0 : 6)

                if isAtSea {
                    // La scena: una fascia di cielo e mare che parte dallo scafo,
                    // col sole o la luna all'ora di bordo e una nave che passa. Il
                    // biglietto ci si appoggia sopra, con la prua nell'acqua.
                    SeaScene(hour: store.shipHour)
                        .frame(height: 250)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, -ticketDraft)
                } else if store.isInPort {
                    // In porto la stessa scena, con la terra e la nave ormeggiata:
                    // prima qui c'era solo il blu dello scafo. Più bassa, perché in
                    // porto sotto il biglietto ci sono il meteo e la carta.
                    SeaScene(hour: store.shipHour, setting: .port)
                        .frame(height: 210)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, -ticketDraft)
                }

                VStack(spacing: 0) {
                    if let behind = behindText(voyage: voyage, moment: moment) {
                        TicketBehind(behind)
                            .padding(.bottom, -14)
                    }
                    BoardingPass(voyage: voyage, moment: moment, focus: store.focus,
                                 now: store.now, offset: store.timeOffset,
                                 fix: position.shipFix(for: voyage, at: store.now),
                                 speedUnit: preferences.speedUnit)
                        .padding(.horizontal, 16)
                }

                ClockChangeNotice(clock: voyage.clock, now: store.now)
                    .padding(.horizontal, 16)
                if case .atSea(_, let destination) = moment,
                   let estimate = ArrivalEstimate.estimate(track: store.recorder.track,
                                                           destination: destination, now: store.now),
                   estimate.isLate {
                    ArrivalDelayNotice(estimate: estimate, port: destination, clock: voyage.clock)
                        .padding(.horizontal, 16)
                }

                chips(moment: moment)
                photoCard
                chartCard(voyage: voyage)
                ashoreRow(voyage: voyage)
                nextCallRow(voyage: voyage, moment: moment)
                if case .inPort = moment { AppleWeatherLink().padding(.horizontal, 16) }
            }
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func dayLine(voyage: Voyage) -> String? {
        if let day = store.today {
            return String(localized: "Giorno \(day.number) di \(store.days.count)")
        }
        if case .beforeVoyage = store.moment {
            return String(localized: "\(voyage.nights) notti · \(voyage.intermediateCalls.count) scali")
        }
        return nil
    }

    /// Il biglietto di dietro: il prossimo scalo, o l'imbarco.
    private func behindText(voyage: Voyage, moment: Voyage.Moment) -> String? {
        let clock = voyage.clock
        switch moment {
        case .inPort(let call):
            guard let index = voyage.calls.firstIndex(where: { $0.id == call.id }),
                  index + 1 < voyage.calls.count else { return nil }
            let next = voyage.calls[index + 1]
            return "\(next.name) · \(relativeDay(next.arrival, clock: clock)) \(clock.time(next.arrival))"
        case .atSea(_, let to):
            // Il biglietto davanti è già verso `to`: dietro c'è lo scalo dopo.
            guard let index = voyage.calls.firstIndex(where: { $0.id == to.id }),
                  index + 1 < voyage.calls.count else { return nil }
            let next = voyage.calls[index + 1]
            return "\(next.name) · \(relativeDay(next.arrival, clock: clock)) \(clock.time(next.arrival))"
        case .beforeVoyage:
            guard voyage.calls.count > 1 else { return nil }
            let next = voyage.calls[1]
            return "\(next.name) · \(Format.dayMonth(next.arrival, clock: clock))"
        case .completed:
            return nil
        }
    }

    /// «oggi», «domani», o la data.
    private func relativeDay(_ date: Date, clock: ShipClock) -> String {
        let today = clock.startOfDay(for: store.now)
        let day = clock.startOfDay(for: date)
        let calendar = clock.calendar(at: today)
        if day == today { return String(localized: "oggi") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), day == tomorrow {
            return String(localized: "domani")
        }
        return Format.dayMonth(date, clock: clock)
    }

    // MARK: Che mare c'è

    /// Il punto di cui chiedere il meteo: dove sei adesso in mare, il porto dove sei
    /// ormeggiato, quello dove ti imbarcherai. Sempre un posto solo.
    private func weatherPoint(moment: Voyage.Moment) -> Coordinate? {
        switch moment {
        case .atSea(let from, let to):
            store.scheduledFix?.coordinate ?? Geo.interpolate(from: from.coordinate,
                                                              to: to.coordinate, fraction: 0.5)
        case .inPort(let call), .beforeVoyage(let call):
            call.coordinate
        case .completed:
            nil
        }
    }

    /// L'ora di cui ha senso chiedere il meteo. Prima dell'imbarco è quando sali;
    /// e se salire è fra due mesi non c'è previsione da dare — i modelli arrivano a
    /// tre giorni.
    private func weatherMoment(_ moment: Voyage.Moment) -> Date? {
        switch moment {
        case .atSea, .inPort: store.now
        case .beforeVoyage(let call):
            call.arrival <= store.now.addingTimeInterval(3 * 86_400) ? call.arrival : nil
        case .completed: nil
        }
    }

    private func mooring(_ moment: Voyage.Moment) -> SeaState.Mooring {
        switch moment {
        case .atSea: .underway
        case .inPort(let call), .beforeVoyage(let call):
            call.berth.kind == .tender ? .tender : .alongside
        case .completed: .alongside
        }
    }

    @ViewBuilder
    private func chips(moment: Voyage.Moment) -> some View {
        if let point = weatherPoint(moment: moment), let when = weatherMoment(moment),
           let conditions = weather.conditions(for: point, at: when), !conditions.isEmpty,
           abs(conditions.time.timeIntervalSince(when)) < 3 * 3600 {
            WeatherChips(conditions: conditions, now: store.now, mooring: mooring(moment))
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
    }

    // MARK: Righe di contorno

    /// La foto della nave, prima della crociera. Una sola volta: se la foto non
    /// c'è, sotto c'è già la rotta, e non la si ripete.
    @ViewBuilder
    private var photoCard: some View {
        if store.isAwaitingDeparture, let photo = photos.photo {
            ShipPhotoCard(photo: photo).padding(.horizontal, 16)
        }
    }

    /// Quanto sei lontano dalla nave. Compare solo quando la domanda ha una risposta:
    /// sei sceso a terra, in un porto, col permesso di posizione concesso.
    @ViewBuilder
    private func ashoreRow(voyage: Voyage) -> some View {
        if let distance = position.distanceToShip(for: voyage, at: store.now) {
            PaperRow(glyph: "figure.walk",
                     title: String(localized: "Sei a \(Format.distance(metres: distance)) dalla nave"),
                     subtitle: String(localized: "in linea d'aria, non lungo la strada"))
                .padding(.horizontal, 16)
        }
    }

    /// L'anteprima della carta, che porta alla carta intera.
    @ViewBuilder
    private func chartCard(voyage: Voyage) -> some View {
        NavigationLink(value: Route.chart) {
            ChartPreviewCard(voyage: voyage,
                             fix: position.shipFix(for: voyage, at: store.now),
                             now: store.now,
                             framing: chartFraming,
                             title: seaArea(voyage: voyage),
                             showsPortNames: store.isAwaitingDeparture,
                             showsGraticule: store.isAwaitingDeparture)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Apri la carta"))
        .padding(.horizontal, 16)
    }

    /// Con che inquadratura si apre la carta: **la stessa della card da cui si
    /// arriva**. Prima della partenza non c'è ancora una nave da inquadrare, quindi
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
        case .beforeVoyage: String(localized: "La rotta")
        case .completed, .none: voyage.calls.last?.name ?? ""
        }
    }

    /// La riga verso il prossimo scalo. Ha la freccia perché porta davvero altrove.
    @ViewBuilder
    private func nextCallRow(voyage: Voyage, moment: Voyage.Moment) -> some View {
        if let next = upcoming(voyage: voyage, moment: moment) {
            NavigationLink(value: Route.port(next)) {
                PaperRow(glyph: "mappin.and.ellipse", title: next.name,
                         subtitle: subtitle(for: next, clock: voyage.clock)) {
                    PaperDisclosure()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
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

/// La fotografia della nave, su carta, col credito che l'autore chiede.
struct ShipPhotoCard: View {
    @Environment(\.livery) private var livery
    let photo: CommonsPhoto

    var body: some View {
        VStack(spacing: 0) {
            // Nell'`overlay` e non figlia diretta: un'immagine `.fill` come figlia
            // detta la larghezza alla colonna e taglia i nomi lunghi.
            Color.clear
                .frame(height: 190)
                .overlay {
                    Image(uiImage: photo.image).resizable().aspectRatio(contentMode: .fill)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(6)
            Text(photo.credit)
                .font(.caption2)
                .foregroundStyle(livery.field)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .paperCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Fotografia della nave, \(photo.credit)"))
    }
}

#Preview("In porto") {
    TodayScreen()
        .environment(VoyageStore.preview)
        .environment(Preferences.ephemeral)
        .environment(PositionService())
        .environment(NotificationScheduler())
        .environment(LiveActivityController())
        .environment(Reachability())
        .environment(MarineWeatherService())
        .preferredColorScheme(.dark)
}

#Preview("In mare") {
    TodayScreen()
        .environment(VoyageStore.previewAtSea)
        .environment(Preferences.ephemeral)
        .environment(PositionService())
        .environment(NotificationScheduler())
        .environment(LiveActivityController())
        .environment(Reachability())
        .environment(MarineWeatherService())
        .preferredColorScheme(.dark)
}
