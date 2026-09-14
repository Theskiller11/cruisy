import Foundation

/// Le coste del mondo, pronte in memoria.
///
/// Natural Earth alla scala 1:50 milioni, di **pubblico dominio**: nessuna licenza da
/// negoziare, nessuna attribuzione dovuta, nessun fornitore che può cambiare i prezzi.
/// Impacchettate nell'app, non scaricate: la carta deve disegnarsi in mezzo
/// all'oceano, dove non c'è rete — che è precisamente il momento in cui serve.
///
/// Il formato è binario e non GeoJSON: 60.000 punti da decodificare in JSON a ogni
/// avvio sarebbero decimi di secondo buttati, mentre qui si legge un blocco di
/// memoria e si finisce. Ogni anello porta con sé il proprio riquadro di ingombro,
/// così scartare ciò che è fuori vista costa quattro confronti invece di scorrere
/// i punti.
public final class Coastline: @unchecked Sendable {

    public struct Ring: Sendable {
        public let start: Int
        public let count: Int
        public let bounds: GeoBounds
    }

    public let points: [Coordinate]
    public let rings: [Ring]

    public static let shared: Coastline = load()

    private init(points: [Coordinate], rings: [Ring]) {
        self.points = points
        self.rings = rings
    }

    /// Gli anelli che toccano il riquadro visibile, dal più grande al più piccolo:
    /// così i continenti finiscono sotto e le isole sopra.
    public func rings(intersecting bounds: GeoBounds) -> [Ring] {
        rings.filter { $0.bounds.intersects(bounds) }
    }

    private static func load() -> Coastline {
        guard let url = Bundle.main.url(forResource: "coastline", withExtension: "bin"),
              let data = try? Data(contentsOf: url),
              data.count > 12
        else { return Coastline(points: [], rings: []) }

        return data.withUnsafeBytes { raw -> Coastline in
            func u32(_ offset: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
            func f32(_ offset: Int) -> Double { Double(raw.loadUnaligned(fromByteOffset: offset, as: Float32.self)) }

            // Se un giorno il formato cambia, meglio una carta vuota di un crollo.
            guard Array(raw[0..<4]) == Array("CRSY".utf8) else {
                assertionFailure("coastline.bin non ha il formato atteso")
                return Coastline(points: [], rings: [])
            }

            let ringCount = u32(8)
            var offset = 12

            var lengths = [Int](repeating: 0, count: ringCount)
            for index in 0..<ringCount { lengths[index] = u32(offset); offset += 4 }

            var boxes = [GeoBounds]()
            boxes.reserveCapacity(ringCount)
            for _ in 0..<ringCount {
                boxes.append(GeoBounds(minLon: f32(offset), minLat: f32(offset + 4),
                                       maxLon: f32(offset + 8), maxLat: f32(offset + 12)))
                offset += 16
            }

            let total = lengths.reduce(0, +)
            var points = [Coordinate]()
            points.reserveCapacity(total)
            for _ in 0..<total {
                points.append(Coordinate(latitude: f32(offset + 4), longitude: f32(offset)))
                offset += 8
            }

            var rings = [Ring]()
            rings.reserveCapacity(ringCount)
            var start = 0
            for index in 0..<ringCount {
                rings.append(Ring(start: start, count: lengths[index], bounds: boxes[index]))
                start += lengths[index]
            }
            return Coastline(points: points, rings: rings)
        }
    }
}
