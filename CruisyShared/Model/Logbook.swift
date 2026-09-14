import Foundation

/// Un porto toccato, con la data in cui ci sei stato.
public struct LoggedPort: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var region: String
    public var coordinate: Coordinate
    public var arrival: Date

    public var id: String { "\(name)|\(arrival.timeIntervalSince1970)" }

    public init(name: String, region: String, coordinate: Coordinate, arrival: Date) {
        self.name = name
        self.region = region
        self.coordinate = coordinate
        self.arrival = arrival
    }
}

/// Una crociera come resta nel diario: la nave, le date, i porti, le miglia.
///
/// È una copia ridotta della `Voyage`, non un riferimento: la crociera viva verrà
/// cancellata per fare posto alla prossima, e il diario deve sopravviverle. È anche
/// il motivo per cui qui non c'è niente di modificabile — un diario che si può
/// riscrivere non è un diario.
public struct LoggedVoyage: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var shipName: String
    public var ports: [LoggedPort]
    /// Miglia dei tratti effettivamente percorsi, ortodromia fra scalo e scalo.
    public var nauticalMiles: Double
    public var seaDays: Int
    /// L'ora di bordo di quella crociera. Le date del diario si leggono con l'ora
    /// che avevi al polso allora, non con quella del fuso in cui ti trovi adesso.
    public var secondsFromGMT: Int
    /// La rotta davvero percorsa, se è stata registrata, alleggerita alla chiusura.
    ///
    /// Quando c'è, `nauticalMiles` viene da lei e non dalle corde fra gli scali: una
    /// nave non va in linea retta, e la differenza si vede.
    public var track: Track?

    public var clock: ShipClock { ShipClock(secondsFromGMT: secondsFromGMT) }

    public var start: Date? { ports.first?.arrival }
    public var end: Date? { ports.last?.arrival }

    public init(id: UUID, shipName: String, ports: [LoggedPort],
                nauticalMiles: Double, seaDays: Int, secondsFromGMT: Int = 0,
                track: Track? = nil) {
        self.track = track
        self.id = id
        self.shipName = shipName
        self.ports = ports
        self.nauticalMiles = nauticalMiles
        self.seaDays = seaDays
        self.secondsFromGMT = secondsFromGMT
    }

    /// La parte di crociera già avvenuta a una certa data.
    ///
    /// Uno scalo entra nel diario quando ci sei arrivato davvero, non quando era in
    /// programma: `now` taglia via il futuro. Passando `.distantFuture` si ottiene
    /// la crociera intera, che è quello che serve quando la si archivia a fine viaggio.
    public static func sailed(_ voyage: Voyage, upTo now: Date) -> LoggedVoyage {
        let reached = voyage.calls.filter { $0.arrival <= now }
        let ports = reached.map {
            LoggedPort(name: $0.name, region: $0.region,
                       coordinate: $0.coordinate, arrival: $0.arrival)
        }

        var miles = 0.0
        for (from, to) in zip(reached, reached.dropFirst()) {
            miles += Geo.nauticalMiles(from: from.coordinate, to: to.coordinate)
        }

        // Un giorno di mare è un giorno in cui non hai toccato terra: si contano i
        // giorni di calendario coperti dalla crociera meno quelli con uno scalo.
        let calendar = voyage.clock.calendar(at: now)
        var seaDays = 0
        if let first = reached.first?.arrival, let last = reached.last?.arrival {
            // La finestra arriva a oggi, non all'ultimo porto toccato: se sei in
            // mezzo a una traversata, oggi è un giorno di mare — e un diario che
            // segna zero mentre guardi l'oceano dal ponte ha torto lui.
            let end = min(now, max(last, voyage.calls.last?.arrival ?? last))
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                               to: calendar.startOfDay(for: end)).day ?? 0
            let ashore = Set(reached.map { calendar.startOfDay(for: $0.arrival) }).count
            seaDays = max(0, days + 1 - ashore)
        }

        return LoggedVoyage(id: voyage.id, shipName: voyage.shipName, ports: ports,
                            nauticalMiles: miles, seaDays: seaDays,
                            // Il diario tiene **uno** scarto, quello dell'imbarco: serve
                            // a scrivere le date della crociera, e le date di una crociera
                            // si contano da quando è cominciata.
                            secondsFromGMT: voyage.clock.secondsFromGMT(
                                at: voyage.calls.first?.arrival ?? now))
    }

    public var isEmpty: Bool { ports.isEmpty }

    // Un diario scritto prima che esistesse l'ora di bordo si legge lo stesso: il
    // campo mancante vale UTC. Meglio una data leggermente spostata che un file
    // che non si apre più.
    private enum CodingKeys: String, CodingKey {
        case id, shipName, ports, nauticalMiles, seaDays, secondsFromGMT
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        shipName = try c.decode(String.self, forKey: .shipName)
        ports = try c.decode([LoggedPort].self, forKey: .ports)
        nauticalMiles = try c.decode(Double.self, forKey: .nauticalMiles)
        seaDays = try c.decode(Int.self, forKey: .seaDays)
        secondsFromGMT = try c.decodeIfPresent(Int.self, forKey: .secondsFromGMT) ?? 0
    }
}

/// Tutte le crociere fatte.
public struct Logbook: Codable, Sendable {
    public var voyages: [LoggedVoyage]

    public init(voyages: [LoggedVoyage] = []) {
        self.voyages = voyages
    }

    /// Inserisce o aggiorna una crociera. La chiave è l'identità della crociera, non
    /// la posizione: riarchiviare la stessa crociera più avanti nel tempo la
    /// aggiorna invece di duplicarla.
    public mutating func record(_ entry: LoggedVoyage) {
        guard !entry.isEmpty else { return }
        if let index = voyages.firstIndex(where: { $0.id == entry.id }) {
            voyages[index] = entry
        } else {
            voyages.append(entry)
        }
        voyages.sort { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    }

    // MARK: I totali

    public var nauticalMiles: Double { voyages.reduce(0) { $0 + $1.nauticalMiles } }
    public var seaDays: Int { voyages.reduce(0) { $0 + $1.seaDays } }

    /// I porti distinti, con la prima volta che ci sei stato e quante volte in tutto.
    public struct Stamp: Hashable, Sendable, Identifiable {
        public var port: LoggedPort
        public var visits: Int
        public var id: String { ShipDirectory.fold(port.name) }
    }

    public var stamps: [Stamp] {
        var byKey: [String: Stamp] = [:]
        for port in voyages.flatMap(\.ports) {
            let key = ShipDirectory.fold(port.name)
            if var existing = byKey[key] {
                existing.visits += 1
                if port.arrival < existing.port.arrival { existing.port = port }
                byKey[key] = existing
            } else {
                byKey[key] = Stamp(port: port, visits: 1)
            }
        }
        return byKey.values.sorted { $0.port.arrival > $1.port.arrival }
    }

    public var ships: [String] {
        var seen = Set<String>()
        return voyages.compactMap { voyage in
            let key = ShipDirectory.fold(voyage.shipName)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return voyage.shipName
        }
    }

    // MARK: I primati

    /// Il porto più a nord e quello più a sud fra tutti quelli toccati.
    public var northernmost: LoggedPort? {
        voyages.flatMap(\.ports).max { $0.coordinate.latitude < $1.coordinate.latitude }
    }

    public var southernmost: LoggedPort? {
        voyages.flatMap(\.ports).min { $0.coordinate.latitude < $1.coordinate.latitude }
    }

    /// La traversata più lunga fra due scali consecutivi, in miglia.
    public struct Crossing: Sendable {
        public var from: LoggedPort
        public var to: LoggedPort
        public var nauticalMiles: Double
    }

    public var longestCrossing: Crossing? {
        var best: Crossing?
        for voyage in voyages {
            for (from, to) in zip(voyage.ports, voyage.ports.dropFirst()) {
                let miles = Geo.nauticalMiles(from: from.coordinate, to: to.coordinate)
                if miles > (best?.nauticalMiles ?? 0) {
                    best = Crossing(from: from, to: to, nauticalMiles: miles)
                }
            }
        }
        return best
    }

    public var isEmpty: Bool { voyages.allSatisfy(\.isEmpty) }
}
