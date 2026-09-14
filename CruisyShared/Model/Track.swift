import Foundation

/// Un punto della rotta davvero percorsa.
public struct TrackPoint: Codable, Hashable, Sendable {
    public var coordinate: Coordinate
    public var at: Date

    public init(coordinate: Coordinate, at: Date) {
        self.coordinate = coordinate
        self.at = at
    }
}

/// La rotta percorsa, punto per punto.
///
/// Serve a due cose che l'itinerario da solo non sa dire: **il filo di dove sei
/// passato davvero** e **le miglia vere**. Le miglia calcolate dagli scali sono la
/// somma delle corde fra un porto e il successivo: una nave non viaggia in linea
/// retta, quindi quel numero è sempre per difetto, e di parecchio quando la rotta
/// costeggia o gira attorno a un'isola.
public struct Track: Codable, Hashable, Sendable {

    public private(set) var points: [TrackPoint]

    public init(points: [TrackPoint] = []) {
        self.points = points.sorted { $0.at < $1.at }
    }

    public var isEmpty: Bool { points.count < 2 }
    public var first: TrackPoint? { points.first }
    public var last: TrackPoint? { points.last }

    /// Quanto si deve essere spostata la nave perché valga la pena segnare un punto.
    ///
    /// Un quarto di miglio: sotto quella soglia si registrerebbe soprattutto il
    /// rumore del GPS, che su una nave ferma in banchina disegnerebbe un gomitolo
    /// da centinaia di punti e falserebbe le miglia verso l'alto.
    public static let minimumSeparation: Double = 0.25

    /// E comunque non più spesso di così, anche se la nave corre.
    public static let minimumInterval: TimeInterval = 120

    /// Aggiunge un punto se porta informazione, e dice se l'ha aggiunto.
    ///
    /// Il filtro è **qui e non in chi chiama**, così vale per ogni sorgente: il GPS
    /// in primo piano, quello in background e un'eventuale importazione si comportano
    /// tutti allo stesso modo.
    @discardableResult
    public mutating func append(_ point: TrackPoint) -> Bool {
        guard let previous = points.last else {
            points.append(point)
            return true
        }
        guard point.at > previous.at else { return false }
        let far = Geo.nauticalMiles(from: previous.coordinate, to: point.coordinate)
            >= Self.minimumSeparation
        let late = point.at.timeIntervalSince(previous.at) >= Self.minimumInterval
        guard far, late else { return false }
        points.append(point)
        return true
    }

    /// Le miglia davvero percorse, sommando i tratti fra i punti.
    public var nauticalMiles: Double {
        zip(points, points.dropFirst()).reduce(0) {
            $0 + Geo.nauticalMiles(from: $1.0.coordinate, to: $1.1.coordinate)
        }
    }

    /// La traccia limitata a una finestra di tempo.
    public func clipped(from: Date, to: Date) -> Track {
        Track(points: points.filter { $0.at >= from && $0.at <= to })
    }

    /// La traccia alleggerita, tenendo la forma.
    ///
    /// Douglas–Peucker: si tiene un punto solo se togliendolo la linea si
    /// allontanerebbe dall'originale più della tolleranza. Una crociera di una
    /// settimana con un punto ogni due minuti fa cinquemila punti; dopo questa
    /// passata ne restano poche centinaia e la rotta è la stessa a vedersi.
    ///
    /// Si semplifica **solo alla chiusura della crociera**, quando la traccia va nel
    /// diario per sempre: durante il viaggio i punti servono tutti, perché è da loro
    /// che escono le miglia.
    public func simplified(toleranceNauticalMiles: Double = 0.5) -> Track {
        guard points.count > 2 else { return self }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        // Iterativa e non ricorsiva: una traccia lunga farebbe esplodere lo stack.
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var worst = 0.0
            var worstIndex = start
            for index in (start + 1)..<end {
                let distance = Self.crossTrack(points[index].coordinate,
                                               from: points[start].coordinate,
                                               to: points[end].coordinate)
                if distance > worst { worst = distance; worstIndex = index }
            }
            if worst > toleranceNauticalMiles {
                keep[worstIndex] = true
                stack.append((start, worstIndex))
                stack.append((worstIndex, end))
            }
        }
        return Track(points: points.enumerated().filter { keep[$0.offset] }.map(\.element))
    }

    /// Quanto dista un punto dal segmento fra altri due, in miglia nautiche.
    ///
    /// Approssimata su un piano locale: alle distanze in gioco — poche miglia fra un
    /// punto e la corda — la curvatura terrestre non cambia il verdetto, e la formula
    /// sferica esatta costerebbe cinquemila arcocoseni per una potatura.
    static func crossTrack(_ point: Coordinate, from a: Coordinate, to b: Coordinate) -> Double {
        let scale = cos(point.latitude * .pi / 180)
        let px = (point.longitude - a.longitude) * scale, py = point.latitude - a.latitude
        let bx = (b.longitude - a.longitude) * scale, by = b.latitude - a.latitude
        let length = bx * bx + by * by
        guard length > 0 else { return Geo.nauticalMiles(from: point, to: a) }
        let t = min(max((px * bx + py * by) / length, 0), 1)
        let dx = px - bx * t, dy = py - by * t
        // Un grado di latitudine è 60 miglia nautiche, per definizione.
        return (dx * dx + dy * dy).squareRoot() * 60
    }
}
