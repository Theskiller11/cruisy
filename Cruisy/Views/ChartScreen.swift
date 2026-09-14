import SwiftUI

/// La carta a tutto schermo, in due livelli.
///
/// Il livello **Carta** si disegna dalla geometria nel bundle: funziona in modalità
/// aereo, che è la ragione per cui esiste. Il livello **Satellite** usa le immagini
/// di Apple, che vanno scaricate — è opzionale, non è il default, e quando la rete
/// manca l'app lo dice invece di lasciare un rettangolo vuoto.
struct ChartScreen: View {
    @Environment(VoyageStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(PositionService.self) private var position
    @Environment(Reachability.self) private var reachability
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Inquadratura iniziale, così il collegamento dalla Home arriva già dove serve.
    var initialFraming: SeaChart.Framing = .ship(spanDegrees: 7.5)

    enum Layer: Hashable { case chart, satellite }

    @State private var layer: Layer = .chart
    @State private var camera: ChartCamera?
    /// Altezza della cornice in basso, misurata: serve al satellite per tenere
    /// l'attribuzione Apple sopra la scheda di stato.
    @State private var bottomFurniture: CGFloat = 220

    private var fix: ShipFix? {
        store.voyage.flatMap { position.shipFix(for: $0, at: store.now) }
    }

    /// Dove sta la nave adesso: il punto a cui il pulsante "torna alla nave" riporta.
    private var shipCoordinate: Coordinate? {
        fix?.coordinate ?? store.voyage?.scheduledFix(at: store.now)?.coordinate
    }

    var body: some View {
        ZStack {
            if let voyage = store.voyage {
                chart(voyage: voyage)
                scrim

                VStack(spacing: 12) {
                    header(voyage: voyage)
                    Spacer(minLength: 0)
                    controls
                    if layer == .satellite, !reachability.isOnline {
                        StaleDataNotice(message: "Senza rete le immagini satellitari non si caricano. La carta nautica funziona lo stesso.")
                    }
                    statusCard(voyage: voyage)
                        .background(GeometryReader { proxy in
                            Color.clear.onAppear { bottomFurniture = proxy.size.height + 96 }
                        })
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                store.background.ignoresSafeArea()
                NoVoyageView()
            }
        }
        // La posizione si chiede **qui**, ora che la Carta è una destinazione e
        // non una scheda. Prima stava in `RootTabView`, e per un motivo: `TabView`
        // costruisce anche le schede non selezionate e ne fa partire i `task`,
        // quindi una richiesta messa qui scattava al primo avvio, dietro
        // l'onboarding, senza che si vedesse a cosa serviva. Una destinazione di
        // navigazione invece si costruisce solo quando ci arrivi davvero, quindi
        // il vincolo è decaduto e la richiesta può stare dove si capisce perché.
        .task {
            guard store.voyage != nil else { return }
            position.requestAccess()
            position.start()
        }
        .onDisappear { position.stop() }
        // Lo swipe dal bordo sinistro torna indietro anche sopra il trascinamento
        // della carta. Sullo sfondo e grande zero: serve solo a stare nella gerarchia
        // dei controller, da dove si arriva al controller di navigazione.
        .background(BackSwipeEnabler().frame(width: 0, height: 0))
        .onAppear {
            if camera == nil { camera = initialCamera() }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-satellite") { layer = .satellite }
            #endif
        }
    }

    // MARK: I due livelli

    @ViewBuilder
    private func chart(voyage: Voyage) -> some View {
        let binding = Binding(
            get: { camera ?? initialCamera() },
            set: { camera = $0 })

        switch layer {
        case .chart:
            InteractiveSeaChart(voyage: voyage, fix: fix, now: store.now,
                                camera: binding, showsPortNames: true)
                .ignoresSafeArea()
        case .satellite:
            SatelliteChart(voyage: voyage, fix: fix, now: store.now, camera: binding,
                           bottomInset: bottomFurniture)
                .ignoresSafeArea()
        }
    }

    private func initialCamera() -> ChartCamera {
        guard let voyage = store.voyage else {
            return ChartCamera(center: Coordinate(latitude: 0, longitude: 0), spanDegrees: 60)
        }
        switch initialFraming {
        case .wholeVoyage:
            return wholeVoyageCamera(voyage)
        case .ship(let span), .location(_, let span), .shipAnchored(let span, _):
            return ChartCamera(center: shipCoordinate ?? voyage.calls.first?.coordinate
                               ?? Coordinate(latitude: 0, longitude: 0),
                               spanDegrees: span)
        case .camera(let camera):
            return camera
        }
    }

    private func wholeVoyageCamera(_ voyage: Voyage) -> ChartCamera {
        let bounds = GeoBounds(covering: voyage.calls.map(\.coordinate)).expanded(by: 1.6)
        return ChartCamera(
            center: Coordinate(latitude: (bounds.minLat + bounds.maxLat) / 2,
                               longitude: (bounds.minLon + bounds.maxLon) / 2),
            spanDegrees: max(bounds.maxLon - bounds.minLon, ChartCamera.minimumSpan))
    }

    // MARK: Comandi

    /// Quanto largo si sta guardando quando si segue la nave.
    private var shipSpan: Double { store.isInPort ? 1.6 : 7.5 }

    /// Vero quando l'inquadratura sta seguendo la nave.
    ///
    /// Serve al pulsante per sapere cosa proporre. Non basta che la nave sia in
    /// vista: sulla rotta intera lo è quasi sempre, ma non è quello che si sta
    /// guardando — perciò conta anche quanto si è larghi.
    private var isFollowingShip: Bool {
        guard let ship = shipCoordinate, let camera else { return false }
        return !camera.isFar(from: ship) && camera.spanDegrees <= shipSpan * 2.2
    }

    /// I due comandi, impilati a destra: sopra il livello, sotto l'inquadratura.
    ///
    /// Un pulsante per cosa, con la sola icona, e **ognuno mostra dove ti porta**,
    /// non dove sei. Prima erano due interruttori a due stati: uno diceva "attorno
    /// alla nave / tutta la rotta", che appena trascini la carta è una bugia —
    /// non sei più in nessuno dei due. Un'azione invece resta vera sempre.
    @ViewBuilder
    private var controls: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                circleButton(
                    systemImage: layer == .chart ? "globe.americas.fill" : "map.fill",
                    label: layer == .chart
                        ? String(localized: "Passa al satellite")
                        : String(localized: "Passa alla carta")) {
                    withAnimation(Motion.settle) {
                        layer = layer == .chart ? .satellite : .chart
                    }
                }

                if let voyage = store.voyage {
                    circleButton(
                        systemImage: isFollowingShip
                            ? "point.topleft.down.to.point.bottomright.curvepath"
                            : "location.fill",
                        label: isFollowingShip
                            ? String(localized: "Mostra tutta la rotta")
                            : String(localized: "Torna alla nave")) {
                        if isFollowingShip {
                            move(to: wholeVoyageCamera(voyage))
                        } else if let ship = shipCoordinate {
                            move(to: ChartCamera(center: ship, spanDegrees: shipSpan))
                        }
                    }
                }
            }
        }
        .fluid(Motion.settle, value: isFollowingShip)
    }

    private func circleButton(systemImage: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        // Tondi davvero: senza, il vetro prende la forma a pastiglia del sistema.
        .buttonBorderShape(.circle)
        .tint(Palette.inkPrimary)
        .accessibilityLabel(Text(label))
    }

    private func move(to target: ChartCamera) {
        // Allineare prima di animare: se la rotta scavalca l'antimeridiano, senza
        // questo la carta attraverserebbe tutto il mondo per arrivare al punto
        // accanto.
        let destination = target.clamped().aligned(to: camera ?? initialCamera())
        if reduceMotion {
            camera = destination
        } else {
            withAnimation(Motion.zoom) { camera = destination }
        }
    }

    // MARK: Cornice

    private var scrim: some View {
        LinearGradient(
            stops: [.init(color: Palette.abyss.opacity(0.72), location: 0),
                    .init(color: .clear, location: 0.24),
                    .init(color: .clear, location: 0.55),
                    .init(color: Palette.abyss.opacity(0.88), location: 0.94)],
            startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func header(voyage: Voyage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // La carta non è più una scheda: ci si arriva dalla card di Oggi, e da
            // qualche parte dev'esserci il modo di tornare indietro. C'è anche lo
            // swipe dal bordo sinistro — vedi `BackSwipeEnabler` — ma un gesto
            // invisibile non è un'affordance: chi non lo conosce resta bloccato.
            circleButton(systemImage: "chevron.backward",
                         label: String(localized: "Indietro")) { dismiss() }
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 10 }

            VStack(alignment: .leading, spacing: 2) {
                Text(voyage.shipName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.inkPrimary)
                if let identifiers = identifiers(voyage) {
                    Text(identifiers)
                        .font(Type.technical)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: 8)
        }
    }

    /// MMSI e IMO sono identificativi pubblici di una nave: dati di fatto.
    private func identifiers(_ voyage: Voyage) -> String? {
        let parts = [voyage.mmsi.map { "MMSI \($0)" }, voyage.imo.map { "IMO \($0)" }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statusCard(voyage: Voyage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveHStack(verticalAlignment: .firstTextBaseline) {
                Text(headline(voyage: voyage))
                    .font(Type.rowTitle)
                    .foregroundStyle(Palette.inkPrimary)
                AdaptiveSpacer()
                if let fix {
                    ProvenanceChip(origin: fix.origin == .schedule ? .estimated : .publishedSchedule,
                                   freshness: fix.freshness(at: store.now))
                }
            }

            if let fix {
                MetricRow(metrics: metrics(voyage: voyage, fix: fix))
                Text(Format.coordinate(fix.coordinate))
                    .font(Type.technical)
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityLabel(Text("Posizione \(Format.coordinate(fix.coordinate))"))
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 28, prominence: .chrome)
    }

    private func headline(voyage: Voyage) -> String {
        switch store.moment {
        case .inPort(let call): String(localized: "Ormeggiata a \(call.name)")
        case .atSea(_, let to): String(localized: "In navigazione verso \(to.name)")
        case .beforeVoyage(let call): String(localized: "Imbarco a \(call.name)")
        case .completed, .none: String(localized: "Crociera conclusa")
        }
    }

    /// Come nel pannello di Oggi: quando il GPS è fermo non dà velocità né rotta, e
    /// invece di inventarle si mostra un'altra grandezza col suo nome vero.
    private func metrics(voyage: Voyage, fix: ShipFix) -> [Metric] {
        var metrics: [Metric] = []
        if let speed = fix.speed, speed > 0.2 {
            metrics.append(Metric(value: Format.speed(knots: speed, unit: preferences.speedUnit),
                                  label: String(localized: "Velocità")))
        }
        if let course = fix.course {
            metrics.append(Metric(value: Format.bearing(course),
                                  label: String(localized: "Rotta"),
                                  spoken: Format.course(course)))
        } else if case .atSea(_, let to) = store.moment {
            let bearing = Geo.bearing(from: fix.coordinate, to: to.coordinate)
            metrics.append(Metric(value: Format.bearing(bearing),
                                  label: String(localized: "Rilevamento"),
                                  spoken: Format.course(bearing)))
        }
        if let miles = voyage.milesRemaining(from: fix, at: store.now) {
            metrics.append(Metric(value: Format.nauticalMiles(miles),
                                  label: String(localized: "Alla meta")))
        }
        return metrics
    }
}
