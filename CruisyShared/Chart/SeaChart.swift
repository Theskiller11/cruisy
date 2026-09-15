import SwiftUI

/// La carta nautica, disegnata in casa.
///
/// Niente MapKit. Il brief metteva una mappa a tutto schermo e, due schermate più in
/// là, scriveva «nessuna rete a bordo»: MapKit scarica le tessere, quindi la
/// schermata più costosa dell'app sarebbe rimasta bianca in mezzo all'oceano, che è
/// il caso d'uso. Qui la geometria è nel bundle e il disegno è un `Canvas`: funziona
/// in modalità aereo, a mille miglia dalla costa, per sempre.
struct SeaChart: View {

    /// Che cosa inquadrare.
    enum Framing: Equatable {
        /// Tutta la crociera, da imbarco a sbarco.
        case wholeVoyage
        /// Attorno alla nave, largo tanti gradi di longitudine.
        case ship(spanDegrees: Double)
        /// Come `ship`, ma con la nave in un punto preciso del riquadro invece che
        /// al centro: serve al widget medio, dove lo spazio libero sta a destra.
        case shipAnchored(spanDegrees: Double, at: UnitPoint)
        /// Inquadratura pilotata a mano, da un gesto.
        case camera(ChartCamera)
        /// Attorno a un punto preciso.
        ///
        /// Serve al dettaglio di uno scalo: prima usava l'inquadratura "attorno alla
        /// nave", che prima della partenza ripiega sul porto d'imbarco — e così ogni
        /// scalo mostrava la carta di San Juan invece della propria.
        case location(Coordinate, spanDegrees: Double)
    }

    let voyage: Voyage
    let fix: ShipFix?
    let now: Date
    var framing: Framing = .wholeVoyage
    var showsPortNames = true
    var showsGraticule = true
    var showsShip = true
    /// Uno scalo da mettere in risalto rispetto agli altri.
    var highlighting: Coordinate?
    /// Margine per lasciare respiro alle etichette dei porti.
    var padding: CGFloat = 0

    private var coastline: Coastline { .shared }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let projection = projection(for: size)
            drawGraticule(in: context, size: size, projection: projection)
            drawLand(in: context, projection: projection)
            drawRoute(in: context, projection: projection)
            drawPorts(in: &context, projection: projection)
            if showsShip { drawShip(in: context, projection: projection) }
        }
        .background(ocean)
        .drawingGroup()
    }

    /// L'oceano: più chiaro in alto, come una carta illuminata da sopra.
    private var ocean: some View {
        RadialGradient(colors: [Color(hex: 0x0D2C46), Color(hex: 0x072033), Color(hex: 0x041524)],
                       center: .top, startRadius: 0, endRadius: 520)
    }

    // MARK: Inquadratura

    private func projection(for size: CGSize) -> ChartProjection {
        switch framing {
        case .wholeVoyage:
            let bounds = GeoBounds(covering: voyage.calls.map(\.coordinate)).expanded(by: 1.6)
            return .fitting(bounds, in: size, padding: padding)
        case .ship(let span):
            let centre = fix?.coordinate
                ?? voyage.scheduledFix(at: now)?.coordinate
                ?? voyage.calls.first?.coordinate
                ?? Coordinate(latitude: 0, longitude: 0)
            return .centred(on: centre, spanDegrees: span, in: size)
        case .shipAnchored(let span, let anchor):
            let centre = fix?.coordinate
                ?? voyage.scheduledFix(at: now)?.coordinate
                ?? voyage.calls.first?.coordinate
                ?? Coordinate(latitude: 0, longitude: 0)
            let base = ChartProjection.centred(on: centre, spanDegrees: span, in: size)
            // Si sposta l'inquadratura di quanto serve perché la nave cada
            // sull'ancora invece che a metà.
            let wanted = CGPoint(x: size.width * anchor.x, y: size.height * anchor.y)
            let now = base.point(centre)
            return ChartProjection(originX: base.originX - Double(wanted.x - now.x) / base.scale,
                                   originY: base.originY - Double(wanted.y - now.y) / base.scale,
                                   scale: base.scale, size: size)
        case .location(let coordinate, let span):
            return .centred(on: coordinate, spanDegrees: span, in: size)
        case .camera(let camera):
            return .centred(on: camera.center, spanDegrees: camera.spanDegrees, in: size)
        }
    }

    // MARK: Strati

    /// Il reticolato di meridiani e paralleli. Dà la scala senza dover scrivere numeri.
    private func drawGraticule(in context: GraphicsContext, size: CGSize, projection: ChartProjection) {
        guard showsGraticule else { return }
        let bounds = projection.visibleBounds
        let span = bounds.maxLon - bounds.minLon
        // Un passo che dia circa sei linee, arrotondato a una taglia leggibile.
        let step = [0.5, 1, 2, 5, 10, 20, 30].first { span / $0 <= 7 } ?? 45

        var path = Path()
        var lon = (bounds.minLon / step).rounded(.up) * step
        while lon <= bounds.maxLon {
            let x = projection.point(Coordinate(latitude: 0, longitude: lon)).x
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            lon += step
        }
        var lat = (bounds.minLat / step).rounded(.up) * step
        while lat <= bounds.maxLat {
            let y = projection.point(Coordinate(latitude: lat, longitude: 0)).y
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            lat += step
        }
        context.stroke(path, with: .color(Color(hex: 0x96CDF0).opacity(0.07)), lineWidth: 0.6)
    }

    /// Le terre emerse. Si disegnano solo gli anelli che toccano la vista.
    private func drawLand(in context: GraphicsContext, projection: ChartProjection) {
        let visible = projection.visibleBounds
        var path = Path()

        for ring in coastline.rings(intersecting: visible) {
            guard ring.count > 2 else { continue }
            let end = ring.start + ring.count
            guard end <= coastline.points.count else { continue }

            path.move(to: projection.point(coastline.points[ring.start]))
            for index in (ring.start + 1)..<end {
                path.addLine(to: projection.point(coastline.points[index]))
            }
            path.closeSubpath()
        }

        context.fill(path, with: .color(Color(hex: 0x12283A)))
        context.stroke(path, with: .color(Color(hex: 0x78BEEB).opacity(0.30)), lineWidth: 0.7)
    }

    /// La rotta: continua dove si è già passati, tratteggiata dove si deve ancora andare.
    ///
    /// I segmenti li calcola `Voyage`, non questa vista: li usa anche la carta
    /// satellitare, e due calcoli separati finirebbero prima o poi per disegnare
    /// due rotte diverse per la stessa nave.
    private func drawRoute(in context: GraphicsContext, projection: ChartProjection) {
        let segments = voyage.routeSegments(at: now, fix: fix)

        func path(_ coordinates: [Coordinate]) -> Path {
            var path = Path()
            let points = Voyage.greatCirclePath(through: coordinates).map(projection.point)
            guard let first = points.first else { return path }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }

        context.stroke(path(segments.ahead), with: .color(Color(hex: 0xB4E1FF).opacity(0.34)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 5]))
        let sailed = path(segments.sailed)
        context.stroke(sailed, with: .color(Palette.underway.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 7, lineCap: .round))
        context.stroke(sailed, with: .color(Palette.underway),
                       style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
    }

    private func drawPorts(in context: inout GraphicsContext, projection: ChartProjection) {
        // I riquadri delle etichette già posate: due nomi sovrapposti non si leggono
        // né l'uno né l'altro, e su una carta fitta di isole succede di continuo.
        var placed: [CGRect] = []

        // Prima lo scalo in risalto, poi gli altri: se lo spazio finisce, a restare
        // senza nome dev'essere un porto qualsiasi, non quello che si sta guardando.
        let ordered = voyage.calls.sorted { a, b in
            (highlighting.map { a.coordinate == $0 } ?? false)
                && !(highlighting.map { b.coordinate == $0 } ?? false)
        }

        for call in ordered {
            let point = projection.point(call.coordinate)
            guard point.x > -40, point.x < projection.size.width + 40,
                  point.y > -40, point.y < projection.size.height + 40 else { continue }

            let isHighlighted = highlighting.map { call.coordinate == $0 } ?? false
            let visited = call.arrival <= now
            let radius: CGFloat = isHighlighted ? 5 : 3.4
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                             width: radius * 2, height: radius * 2))
            if isHighlighted {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 13, y: point.y - 13,
                                                    width: 26, height: 26)),
                             with: .color(Palette.action.opacity(0.22)))
            }
            context.fill(dot, with: .color(isHighlighted ? Palette.action
                                           : visited ? Palette.underway : Color(hex: 0x091A28)))
            context.stroke(dot, with: .color(visited || isHighlighted ? Color(hex: 0x041420)
                                             : Color(hex: 0xBEE6FF).opacity(0.75)),
                           lineWidth: 1.4)

            let margin: CGFloat = 58
            guard showsPortNames,
                  point.x > margin, point.x < projection.size.width - margin,
                  point.y > margin, point.y < projection.size.height - margin
            else { continue }

            let label = context.resolve(Text(call.name)
                .font(.system(size: isHighlighted ? 12 : 10.5, weight: .semibold)))
            let size = label.measure(in: projection.size)
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y + 9)
            let frame = CGRect(origin: origin, size: size).insetBy(dx: -3, dy: -2)

            guard !placed.contains(where: { $0.intersects(frame) }) else { continue }
            placed.append(frame)

            context.draw(label, at: CGPoint(x: point.x, y: point.y + 15), anchor: .center)
        }
    }

    /// La nave: un triangolo orientato come la prua, con l'alone che la fa trovare
    /// subito anche in mezzo a una carta piena di cose.
    private func drawShip(in context: GraphicsContext, projection: ChartProjection) {
        guard let fix else { return }
        let point = projection.point(fix.coordinate)

        context.fill(Path(ellipseIn: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)),
                     with: .color(Palette.underway.opacity(0.10)))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 9.5, y: point.y - 9.5, width: 19, height: 19)),
                     with: .color(Palette.underway.opacity(0.22)))

        var hull = Path()
        hull.move(to: CGPoint(x: 0, y: -8))
        hull.addLine(to: CGPoint(x: 5.4, y: 7))
        hull.addLine(to: CGPoint(x: 0, y: 4.2))
        hull.addLine(to: CGPoint(x: -5.4, y: 7))
        hull.closeSubpath()

        let oriented = hull
            .applying(CGAffineTransform(rotationAngle: (fix.course ?? 0) * .pi / 180))
            .applying(CGAffineTransform(translationX: point.x, y: point.y))

        context.fill(oriented, with: .color(Color(hex: 0xEAFAF6)))
        context.stroke(oriented, with: .color(Color(hex: 0x041420).opacity(0.55)), lineWidth: 0.8)
    }
}

/// Perché la carta si muova invece di saltare.
///
/// `withAnimation { camera = altro }` da solo **non anima niente** qui: un `Canvas`
/// non interpola il proprio contenuto, si limita a ridisegnarsi col valore nuovo.
/// Per settimane le molle attorno ai cambi d'inquadratura non hanno prodotto un solo
/// fotogramma intermedio — il gesto di lancio, l'assestamento del pizzico, il doppio
/// tocco e il passaggio "nave ↔ tutta la rotta" erano tutti scatti secchi.
///
/// `Animatable` è ciò che chiude il cerchio: SwiftUI interpola questi tre numeri e
/// riassegna il `framing` a ogni fotogramma, così il `Canvas` si ridisegna lungo il
/// percorso invece che solo alla fine. Fuori da `withAnimation` non cambia nulla,
/// quindi i gesti restano incollati al dito.
///
/// I tre numeri non sono latitudine, longitudine e ampiezza così come stanno:
///
/// - la latitudine passa per **la Y di Mercatore**, se no verso i poli la carta
///   accelera e rallenta da sola durante una panoramica che dovrebbe essere uniforme;
/// - l'ampiezza passa per il **logaritmo**, perché lo zoom si percepisce in rapporti
///   e non in differenze: da 1,6° a 60° in scala lineare si spalancherebbe subito per
///   poi strisciare, mentre in scala logaritmica la crescita si sente costante.
extension SeaChart: @preconcurrency Animatable {
    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get {
            guard case .camera(let camera) = framing else { return .init(.init(0, 0), 0) }
            return .init(.init(Mercator.worldY(latitude: camera.center.latitude),
                               camera.center.longitude),
                         log(max(camera.spanDegrees, 0.001)))
        }
        set {
            guard case .camera = framing else { return }
            framing = .camera(ChartCamera(
                center: Coordinate(latitude: Mercator.latitude(worldY: newValue.first.first),
                                   longitude: newValue.first.second),
                spanDegrees: exp(newValue.second)))
        }
    }
}
