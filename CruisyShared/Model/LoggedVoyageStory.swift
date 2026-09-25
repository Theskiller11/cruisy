import Foundation

/// Una crociera del diario raccontata: le tratte, i giorni, la rotta da disegnare,
/// i primati.
///
/// È tutto calcolo, niente viste, perché è qui che si decide che cosa è misurato
/// e che cosa no: una tratta senza traccia non deve passare per percorsa, e le
/// miglia di un giorno di mare non devono comparire due volte. Sono regole da
/// provare con un test, non da guardare a occhio.
public extension LoggedVoyage {

    // MARK: Le tratte

    /// Da un porto al successivo.
    struct Leg: Hashable, Sendable {
        public var from: LoggedPort
        public var to: LoggedPort
        public var nauticalMiles: Double
        /// Vero se il telefono ha registrato la tratta: almeno metà della strada
        /// sta nella traccia. Se no le miglia sono la corda fra i due porti.
        public var isRecorded: Bool
    }

    /// Le tratte fra un porto e l'altro, con le miglia della traccia dove c'è.
    ///
    /// Una tratta registrata conta la traccia **più** i pezzi mancanti ai due capi
    /// in linea retta: la registrazione parte e si ferma quando vuole, e senza
    /// quei pezzi una tratta verrebbe più corta della corda, che è impossibile.
    func legs(track: Track?) -> [Leg] {
        zip(ports, ports.dropFirst()).map { from, to in
            let chord = Geo.nauticalMiles(from: from.coordinate, to: to.coordinate)
            guard let clipped = track?.clipped(from: from.arrival, to: to.arrival),
                  !clipped.isEmpty, let first = clipped.first, let last = clipped.last,
                  clipped.nauticalMiles >= chord / 2
            else { return Leg(from: from, to: to, nauticalMiles: chord, isRecorded: false) }
            let miles = Geo.nauticalMiles(from: from.coordinate, to: first.coordinate)
                + clipped.nauticalMiles
                + Geo.nauticalMiles(from: last.coordinate, to: to.coordinate)
            return Leg(from: from, to: to, nauticalMiles: max(miles, chord), isRecorded: true)
        }
    }

    // MARK: I giorni

    /// Un giorno della crociera, com'è andato.
    enum Day: Hashable, Sendable, Identifiable {
        /// Uno scalo. `leg` è la tratta che ci ha portato, **solo** se non c'è
        /// stato un giorno di mare prima: in quel caso le miglia le dice lui.
        case port(LoggedPort, leg: Leg?)
        /// Un giorno senza terra, con la tratta che si stava facendo.
        case sea(Date, leg: Leg?)

        public var id: String {
            switch self {
            case .port(let port, _): "p\(port.id)"
            case .sea(let date, _): "s\(date.timeIntervalSince1970)"
            }
        }
    }

    /// I giorni dal primo scalo all'ultimo, uno per riga.
    ///
    /// - Parameter through: fino a che giorno contare. Per una crociera in corso è
    ///   oggi: se sei in mezzo a una traversata, oggi è un giorno di mare anche se
    ///   il porto dopo non c'è ancora.
    func days(track: Track?, through: Date? = nil) -> [Day] {
        guard let first = ports.first, let last = ports.last else { return [] }
        let calendar = clock.calendar(at: first.arrival)
        let legs = legs(track: track)
        let start = calendar.startOfDay(for: first.arrival)
        let end = calendar.startOfDay(for: max(last.arrival, through ?? last.arrival))

        var days: [Day] = []
        var cursor = start
        var seaSinceLastPort = false
        while cursor <= end {
            let arrivals = ports.enumerated().filter { calendar.isDate($0.element.arrival, inSameDayAs: cursor) }
            if arrivals.isEmpty {
                // La tratta in corso è quella che finisce nel primo porto dopo oggi.
                let next = ports.firstIndex { $0.arrival > cursor }
                let leg = next.flatMap { $0 > 0 ? legs[$0 - 1] : nil }
                days.append(.sea(cursor, leg: seaSinceLastPort ? nil : leg))
                seaSinceLastPort = true
            } else {
                for (index, port) in arrivals {
                    let leg = index > 0 && !seaSinceLastPort ? legs[index - 1] : nil
                    days.append(.port(port, leg: leg))
                    seaSinceLastPort = false
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    // MARK: La rotta da disegnare

    /// La rotta divisa in quello che il telefono ha visto e quello che manca.
    struct RouteSketch: Hashable, Sendable {
        /// I tratti registrati, ognuno una spezzata continua.
        public var recorded: [[Coordinate]]
        /// I tratti senza traccia, in linea retta fra i loro capi.
        public var gaps: [[Coordinate]]
    }

    /// Oltre questa pausa fra due punti la traccia si considera interrotta: il
    /// registratore segna un punto almeno ogni pochi minuti quando la nave si muove.
    static let trackBreak: TimeInterval = 45 * 60

    /// Sotto questa distanza un buco non si disegna: sarebbe un trattino dentro
    /// il porto, dove la nave era ferma.
    static let negligibleGap: Double = 3

    func routeSketch(track: Track?) -> RouteSketch {
        var recorded: [[Coordinate]] = []
        var gaps: [[Coordinate]] = []

        // Le spezzate registrate, tagliate dove il telefono ha smesso di ascoltare.
        if let track, !track.isEmpty {
            var run: [TrackPoint] = []
            for point in track.points {
                if let previous = run.last, point.at.timeIntervalSince(previous.at) > Self.trackBreak {
                    if run.count > 1 { recorded.append(run.map(\.coordinate)) }
                    if Geo.nauticalMiles(from: previous.coordinate, to: point.coordinate) > Self.negligibleGap {
                        gaps.append([previous.coordinate, point.coordinate])
                    }
                    run = []
                }
                run.append(point)
            }
            if run.count > 1 { recorded.append(run.map(\.coordinate)) }
        }

        // Ai capi di ogni tratta, quello che la traccia non copre.
        for (from, to) in zip(ports, ports.dropFirst()) {
            let clipped = track?.clipped(from: from.arrival, to: to.arrival)
            guard let clipped, let first = clipped.first, let last = clipped.last, clipped.points.count > 1 else {
                gaps.append([from.coordinate, to.coordinate])
                continue
            }
            if Geo.nauticalMiles(from: from.coordinate, to: first.coordinate) > Self.negligibleGap {
                gaps.append([from.coordinate, first.coordinate])
            }
            if Geo.nauticalMiles(from: last.coordinate, to: to.coordinate) > Self.negligibleGap {
                gaps.append([last.coordinate, to.coordinate])
            }
        }
        return RouteSketch(recorded: recorded, gaps: gaps)
    }

    // MARK: I primati

    var longestLeg: Leg? { legs(track: track).max { $0.nauticalMiles < $1.nauticalMiles } }

    var northernmost: LoggedPort? { ports.max { $0.coordinate.latitude < $1.coordinate.latitude } }
    var southernmost: LoggedPort? { ports.min { $0.coordinate.latitude < $1.coordinate.latitude } }

    /// Le notti a bordo: dal giorno del primo scalo a quello dell'ultimo.
    var nights: Int {
        guard let start, let end else { return 0 }
        let calendar = clock.calendar(at: start)
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                       to: calendar.startOfDay(for: end)).day ?? 0
    }
}

public extension Track {

    /// La velocità più alta tenuta per almeno mezz'ora.
    struct Speed: Hashable, Sendable {
        public var knots: Double
        public var at: Date
    }

    /// Su finestre di mezz'ora e **in linea retta** dal primo all'ultimo punto
    /// della finestra, non sommando i passi: fra due punti vicini basta un salto
    /// del GPS di mezzo miglio per inventare una nave a quaranta nodi, e la somma
    /// dei passi lo conta due volte, all'andata e al ritorno. La linea retta sbaglia
    /// per difetto quando la nave vira, che per un primato è il verso giusto.
    /// E oltre i trenta nodi non si crede a niente: nessuna nave da crociera ci
    /// arriva, e un numero così in un diario è una bugia.
    func topSpeed(window: TimeInterval = 30 * 60, ceiling: Double = 30) -> Speed? {
        var best: Speed?
        var end = 0
        for start in points.indices {
            end = max(end, start)
            while end + 1 < points.count, points[end].at.timeIntervalSince(points[start].at) < window {
                end += 1
            }
            let elapsed = points[end].at.timeIntervalSince(points[start].at)
            // Una finestra che scavalca un buco nella traccia non misura niente.
            guard elapsed >= window, elapsed <= window * 2 else { continue }
            let knots = Geo.nauticalMiles(from: points[start].coordinate, to: points[end].coordinate)
                / (elapsed / 3600)
            if knots <= ceiling, knots > (best?.knots ?? 0) {
                best = Speed(knots: knots, at: points[start].at)
            }
        }
        return best
    }
}
