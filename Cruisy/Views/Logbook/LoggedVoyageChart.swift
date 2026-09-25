import SwiftUI

/// La carta di una crociera del diario: le coste, la rotta, i porti numerati.
///
/// È l'unico posto in cui la linea percorsa sopravvive alla crociera. Nel Diario
/// tutte le rotte insieme diventavano un gomitolo in cui non se ne leggeva
/// nessuna; qui ce n'è una sola, e si vede che cosa è misurato e che cosa no:
/// piena dove il telefono ha registrato, tratteggiata dove si passa in linea retta
/// fra gli scali.
///
/// Stesso disegnatore di coste di `SeaChart`, stessi colori da carta: ma quella
/// sa di una crociera viva, di una nave e di un adesso; questa di un ricordo.
struct LoggedVoyageChart: View {
    let entry: LoggedVoyage
    let track: Track?
    /// Lo spazio in alto che la barra di stato e i pulsanti coprono.
    var topInset: CGFloat = 0

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let sketch = entry.routeSketch(track: track)
            let everything = entry.ports.map(\.coordinate) + sketch.recorded.flatMap { $0 }
            guard !everything.isEmpty else { return }
            // Il riquadro della rotta, allargato quanto basta per le etichette, e
            // mai più stretto di qualche grado: una crociera di due porti vicini
            // mostrerebbe tre scogli ingranditi e nessuna costa.
            var bounds = GeoBounds(covering: everything)
            let spread = max(bounds.maxLon - bounds.minLon, bounds.maxLat - bounds.minLat)
            bounds = bounds.expanded(by: max(0.8, spread * 0.12) + max(0, (4 - spread) / 2))
            let area = CGSize(width: size.width, height: size.height - topInset)
            let fitted = ChartProjection.fitting(bounds, in: area, padding: 18)
            let projection = ChartProjection(originX: fitted.originX,
                                             originY: fitted.originY - Double(topInset) / fitted.scale,
                                             scale: fitted.scale, size: size)

            drawLand(in: context, projection: projection)
            drawGaps(sketch.gaps, in: context, projection: projection)
            drawRecorded(sketch.recorded, in: context, projection: projection)
            drawPorts(in: context, projection: projection)
        }
        .background(RadialGradient(colors: [Color(hex: 0x0D2C46), Color(hex: 0x072033), Color(hex: 0x041524)],
                                   center: .top, startRadius: 0, endRadius: 520))
        .drawingGroup()
        .accessibilityElement()
        .accessibilityLabel(Text(spoken))
    }

    private func drawLand(in context: GraphicsContext, projection: ChartProjection) {
        let coastline = Coastline.shared
        var path = Path()
        for ring in coastline.rings(intersecting: projection.visibleBounds) {
            let end = ring.start + ring.count
            guard ring.count > 2, end <= coastline.points.count else { continue }
            path.move(to: projection.point(coastline.points[ring.start]))
            for index in (ring.start + 1)..<end {
                path.addLine(to: projection.point(coastline.points[index]))
            }
            path.closeSubpath()
        }
        context.fill(path, with: .color(Color(hex: 0x1A3650)))
        context.stroke(path, with: .color(Color(hex: 0x78BEEB).opacity(0.32)), lineWidth: 0.7)
    }

    private func polyline(_ coordinates: [Coordinate], projection: ChartProjection) -> Path {
        var path = Path()
        guard let first = coordinates.first else { return path }
        path.move(to: projection.point(first))
        for coordinate in coordinates.dropFirst() { path.addLine(to: projection.point(coordinate)) }
        return path
    }

    private func drawGaps(_ gaps: [[Coordinate]], in context: GraphicsContext, projection: ChartProjection) {
        for gap in gaps {
            // Sul cerchio massimo, come la rotta di `SeaChart`: una traversata
            // oceanica in linea retta su Mercatore passerebbe dove nessuna nave va.
            let path = polyline(Voyage.greatCirclePath(through: gap), projection: projection)
            context.stroke(path, with: .color(Color(hex: 0xDCEBF7).opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
        }
    }

    private func drawRecorded(_ runs: [[Coordinate]], in context: GraphicsContext, projection: ChartProjection) {
        for run in runs {
            let path = polyline(run, projection: projection)
            context.stroke(path, with: .color(ChartInk.route.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(ChartInk.route),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    /// I porti numerati nell'ordine in cui li hai toccati. Un porto toccato due
    /// volte ha due numeri, uno accanto all'altro: è andata così.
    private func drawPorts(in context: GraphicsContext, projection: ChartProjection) {
        var placed: [CGRect] = []
        var seen: [Coordinate: Int] = [:]
        for (index, port) in entry.ports.enumerated() {
            var point = projection.point(port.coordinate)
            let repeats = seen[port.coordinate, default: 0]
            seen[port.coordinate] = repeats + 1
            point.x += CGFloat(repeats) * 15

            let disc = Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
            context.fill(disc, with: .color(Color(hex: 0x041524)))
            context.stroke(disc, with: .color(ChartInk.route), lineWidth: 1.6)
            context.draw(Text("\(index + 1)")
                .font(.system(size: 9, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white), at: point)

            guard repeats == 0 else { continue }
            let label = context.resolve(Text(port.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88)))
            let measured = label.measure(in: projection.size)
            // Prima a destra, poi a sinistra, poi sotto: il primo posto libero.
            let candidates = [
                CGPoint(x: point.x + 12 + measured.width / 2, y: point.y),
                CGPoint(x: point.x - 12 - measured.width / 2, y: point.y),
                CGPoint(x: point.x, y: point.y + 16),
                CGPoint(x: point.x, y: point.y - 16),
            ]
            for centre in candidates {
                let frame = CGRect(x: centre.x - measured.width / 2, y: centre.y - measured.height / 2,
                                   width: measured.width, height: measured.height).insetBy(dx: -3, dy: -2)
                guard frame.minX > 4, frame.maxX < projection.size.width - 4,
                      !placed.contains(where: { $0.intersects(frame) }) else { continue }
                placed.append(frame)
                placed.append(CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
                context.draw(label, at: centre)
                break
            }
        }
    }

    private var spoken: String {
        let names = entry.ports.map(\.name).joined(separator: ", ")
        let sketch = entry.routeSketch(track: track)
        let note = sketch.recorded.isEmpty
            ? String(localized: "rotta non registrata, in linea retta fra gli scali")
            : String(localized: "rotta registrata dal telefono")
        return String(localized: "Carta della crociera: \(names). \(note)")
    }
}
