import Foundation

/// Che cosa è uno scalo dentro il viaggio.
public enum CallRole: String, Codable, Sendable {
    case embarkation, port, disembarkation
}

/// Come si scende: passerella o tender.
///
/// Non è cosmesi. Col tender il rientro richiede la coda al pontile e l'ultima corsa
/// è ben prima dell'all aboard, quindi cambia quanto margine serve.
public struct Berth: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case dock, tender }

    public var kind: Kind
    /// Come "Amber Cove · Pier 2". Facoltativo: spesso si sa solo la mattina.
    public var name: String?

    public init(kind: Kind, name: String? = nil) {
        self.kind = kind
        self.name = name
    }

    public var label: String {
        switch kind {
        case .dock: String(localized: "ormeggio", comment: "Tipo di attracco")
        case .tender: String(localized: "tender", comment: "Tipo di attracco")
        }
    }
}

/// Uno scalo. Tutti gli istanti sono UTC: l'ora di bordo è una questione di resa.
public struct PortCall: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Paese o regione, per la riga sotto il nome.
    public var region: String
    public var coordinate: Coordinate
    /// Il fuso civile del porto, es. `America/Santo_Domingo`. Nullo per uno scalo
    /// digitato a mano che non sta nell'elenco: in quel caso l'ora di bordo ripiega
    /// sull'ora nautica della sua longitudine.
    public var timeZoneIdentifier: String?
    public var role: CallRole
    public var arrival: Date
    /// Nullo allo sbarco finale: da lì non si riparte.
    public var departure: Date?
    /// L'istante che conta davvero. Nullo allo sbarco finale.
    public var allAboard: Date?
    public var berth: Berth
    /// Da dove vengono questi orari. `userEdited` quando chi è a bordo li corregge
    /// dopo un annuncio, e in quel caso vincono su tutto.
    public var scheduleOrigin: CountdownOrigin

    public init(id: UUID = UUID(), name: String, region: String, coordinate: Coordinate,
                timeZoneIdentifier: String? = nil,
                role: CallRole = .port, arrival: Date, departure: Date? = nil,
                allAboard: Date? = nil, berth: Berth = Berth(kind: .dock),
                scheduleOrigin: CountdownOrigin = .publishedSchedule) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.id = id
        self.name = name
        self.region = region
        self.coordinate = coordinate
        self.role = role
        self.arrival = arrival
        self.departure = departure
        self.allAboard = allAboard
        self.berth = berth
        self.scheduleOrigin = scheduleOrigin
    }

    /// Fino a quando la nave è ferma qui. Allo sbarco coincide con l'arrivo.
    public var castOff: Date { departure ?? arrival }

    /// Durata della sosta.
    public var duration: TimeInterval { castOff.timeIntervalSince(arrival) }

    /// Vero se l'istante cade dentro la sosta.
    public func covers(_ date: Date) -> Bool { date >= arrival && date <= castOff }
}

/// Una crociera: la nave, l'ora di bordo, e gli scali in ordine.
///
/// I giorni di mare non sono memorizzati: si ricavano dai buchi fra uno scalo e il
/// successivo. Un dato derivato non può andare fuori sincrono con quello da cui deriva.
public struct Voyage: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var shipName: String
    /// Identificativi pubblici della nave. Dati di fatto, non materiale di terzi.
    public var mmsi: String?
    public var imo: String?
    public var clock: ShipClock
    /// Scali in ordine di arrivo. Il primo è l'imbarco, l'ultimo lo sbarco.
    public var calls: [PortCall]
    /// Quando è stata modificata l'ultima volta.
    ///
    /// Opzionale per poter rileggere i file salvati prima che questo campo esistesse.
    /// Serve a decidere chi vince quando la stessa crociera è stata toccata su due
    /// dispositivi: vince la modifica più recente, che per un itinerario personale è
    /// la regola giusta — l'ultima correzione è quella fatta guardando il programma
    /// di bordo.
    public var updatedAt: Date?

    public init(id: UUID = UUID(), shipName: String, mmsi: String? = nil, imo: String? = nil,
                clock: ShipClock, calls: [PortCall], updatedAt: Date? = nil) {
        self.id = id
        self.shipName = shipName
        self.mmsi = mmsi
        self.imo = imo
        self.clock = clock
        self.calls = calls.sorted { $0.arrival < $1.arrival }
        self.updatedAt = updatedAt
    }

    /// Vero se questa copia è più recente dell'altra. Una crociera senza data perde
    /// contro una che ce l'ha: viene da prima che il campo esistesse.
    public func isNewer(than other: Voyage) -> Bool {
        switch (updatedAt, other.updatedAt) {
        case (let mine?, let theirs?): return mine > theirs
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return false
        }
    }

    public var embarkation: PortCall? { calls.first }
    public var disembarkation: PortCall? { calls.last }
    /// Solo gli scali intermedi, quelli con un all aboard da rispettare.
    public var intermediateCalls: [PortCall] { calls.dropFirst().dropLast() }

    public var startsAt: Date? { calls.first?.arrival }
    public var endsAt: Date? { calls.last?.arrival }

    /// Notti a bordo, come si contano nei cataloghi.
    public var nights: Int {
        guard let start = embarkation?.castOff, let end = endsAt else { return 0 }
        // Ogni estremo con la **sua** mezzanotte di bordo, perché fra i due l'orologio
        // può essersi spostato. Poi si arrotonda: un'ora di scarto non deve poter
        // aggiungere o togliere una notte al conteggio di un catalogo.
        let from = clock.startOfDay(for: start), to = clock.startOfDay(for: end)
        return max(0, Int((to.timeIntervalSince(from) / 86_400).rounded()))
    }

    // MARK: Dove siamo

    /// In che fase del viaggio cade un istante.
    public enum Moment: Equatable, Sendable {
        /// Non si è ancora imbarcati.
        case beforeVoyage(next: PortCall)
        /// Fermi in un porto.
        case inPort(PortCall)
        /// In navigazione fra due scali.
        case atSea(from: PortCall, to: PortCall)
        /// Sbarcati.
        case completed
    }

    public func moment(at now: Date) -> Moment? {
        guard let first = calls.first, let last = calls.last else { return nil }
        if now < first.arrival { return .beforeVoyage(next: first) }
        if now > last.arrival { return .completed }
        if let berthed = calls.first(where: { $0.covers(now) }) { return .inPort(berthed) }
        for (previous, next) in zip(calls, calls.dropFirst()) where now > previous.castOff && now < next.arrival {
            return .atSea(from: previous, to: next)
        }
        return .completed
    }

    // MARK: L'unica cosa che conta adesso

    /// A che cosa punta il countdown grande.
    public enum FocusKind: Equatable, Sendable {
        case boarding(PortCall)
        case allAboard(PortCall)
        case sailAway(PortCall)
        case arrival(PortCall)
    }

    /// Il countdown in primo piano, con la sua provenienza.
    ///
    /// Un solo numero per volta: se ce ne fossero due a pari peso, chi guarda deve
    /// scegliere, e questa è un'app che si consulta di corsa in banchina.
    public struct Focus: Equatable, Sendable {
        public let kind: FocusKind
        public let countdown: Countdown

        public var port: PortCall {
            switch kind {
            case .boarding(let c), .allAboard(let c), .sailAway(let c), .arrival(let c): c
            }
        }
    }

    public func focus(at now: Date) -> Focus? {
        guard let moment = moment(at: now) else { return nil }
        switch moment {
        case .beforeVoyage(let call):
            let target = call.allAboard ?? call.arrival
            // L'attesa prima dell'imbarco non ha un inizio naturale: si prende una
            // finestra di 24 ore, così l'anello resta leggibile invece di rimanere
            // quasi vuoto per settimane.
            return Focus(kind: .boarding(call),
                         countdown: Countdown(start: target.addingTimeInterval(-86_400),
                                              target: target, origin: call.scheduleOrigin))

        case .inPort(let call):
            if let allAboard = call.allAboard, now < allAboard {
                return Focus(kind: .allAboard(call),
                             countdown: Countdown(start: call.arrival, target: allAboard,
                                                  origin: call.scheduleOrigin))
            }
            if let departure = call.departure, now < departure {
                // Passato l'all aboard resta la partenza, ma solo come informazione.
                return Focus(kind: .sailAway(call),
                             countdown: Countdown(start: call.allAboard ?? call.arrival,
                                                  target: departure, origin: call.scheduleOrigin))
            }
            return nil

        case .atSea(let from, let to):
            return Focus(kind: .arrival(to),
                         countdown: Countdown(start: from.castOff, target: to.arrival,
                                              origin: to.scheduleOrigin))

        case .completed:
            return nil
        }
    }

    // MARK: Posizione dedotta dagli orari

    /// Dove dovrebbe essere la nave secondo il solo itinerario.
    ///
    /// È la rete di sicurezza: nessun permesso, nessuna rete, nessun fornitore. Meno
    /// precisa di un GPS ma sempre disponibile, e dichiara di essere una stima.
    public func scheduledFix(at now: Date) -> ShipFix? {
        guard let moment = moment(at: now) else { return nil }
        switch moment {
        case .beforeVoyage(let call):
            return ShipFix(coordinate: call.coordinate, timestamp: now, origin: .schedule)

        case .inPort(let call):
            return ShipFix(coordinate: call.coordinate, timestamp: now, speed: 0, origin: .schedule)

        case .atSea(let from, let to):
            let total = to.arrival.timeIntervalSince(from.castOff)
            let fraction = total > 0 ? now.timeIntervalSince(from.castOff) / total : 0
            let here = Geo.interpolate(from: from.coordinate, to: to.coordinate, fraction: fraction)
            let miles = Geo.nauticalMiles(from: from.coordinate, to: to.coordinate)
            let hours = total / 3600
            return ShipFix(coordinate: here, timestamp: now,
                           course: Geo.bearing(from: here, to: to.coordinate),
                           speed: hours > 0 ? miles / hours : nil,
                           origin: .schedule)

        case .completed:
            return calls.last.map { ShipFix(coordinate: $0.coordinate, timestamp: now, speed: 0, origin: .schedule) }
        }
    }

    /// La rotta spezzata in due: quella già percorsa e quella che resta.
    ///
    /// Sta qui e non dentro un disegnatore perché la usano sia la carta vettoriale
    /// sia quella satellitare: se ognuna se la calcolasse per conto suo, prima o poi
    /// mostrerebbero due rotte diverse per la stessa nave.
    ///
    /// La parte percorsa arriva fino alla posizione **attuale**, non all'ultimo porto:
    /// altrimenti a metà traversata la scia si fermerebbe al porto di partenza e la
    /// nave sembrerebbe staccata dalla propria rotta.
    func routeSegments(at now: Date, fix: ShipFix?) -> (sailed: [Coordinate], ahead: [Coordinate]) {
        guard calls.count > 1 else { return ([], []) }
        let here = fix?.coordinate ?? scheduledFix(at: now)?.coordinate
        let passed = max(calls.filter { $0.arrival <= now }.count, 1)

        let sailed = calls.prefix(passed).map(\.coordinate) + (here.map { [$0] } ?? [])
        let ahead = (here.map { [$0] } ?? []) + calls.dropFirst(passed).map(\.coordinate)
        return (sailed, ahead)
    }

    /// Una spezzata che segue il cerchio massimo fra due punti, così su tratte lunghe
    /// la linea non taglia dove la nave non passa.
    static func greatCircle(from a: Coordinate, to b: Coordinate, segmentMiles: Double = 40) -> [Coordinate] {
        let steps = max(2, Int(Geo.nauticalMiles(from: a, to: b) / segmentMiles))
        return (0...steps).map {
            Geo.interpolate(from: a, to: b, fraction: Double($0) / Double(steps))
        }
    }

    /// La spezzata completa di una sequenza di punti, seguendo i cerchi massimi.
    static func greatCirclePath(through coordinates: [Coordinate]) -> [Coordinate] {
        guard coordinates.count > 1 else { return coordinates }
        var path = [coordinates[0]]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            path.append(contentsOf: greatCircle(from: a, to: b).dropFirst())
        }
        return path
    }

    /// Miglia nautiche che restano fino al prossimo scalo, da una posizione data.
    public func milesRemaining(from fix: ShipFix, at now: Date) -> Double? {
        guard case .atSea(_, let to) = moment(at: now) else { return nil }
        return Geo.nauticalMiles(from: fix.coordinate, to: to.coordinate)
    }
}
