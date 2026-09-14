import Foundation

/// Da dove arriva una posizione.
///
/// L'ordine di preferenza è deliberato e ribalta l'idea del brief. L'AIS terrestre
/// non copre il mare aperto, che è proprio il giorno di mare; quello satellitare
/// costa e ha licenze incerte. Ma chi usa l'app **è sulla nave**: il GPS del telefono
/// è la posizione della nave, e funziona in mezzo all'oceano senza un byte di rete.
public enum PositionOrigin: String, Codable, Sendable {
    /// GPS del telefono. Preciso, offline, gratis — quando sei a bordo.
    case device
    /// Interpolata lungo l'itinerario dagli orari. Sempre disponibile, mai precisa.
    case schedule
    /// Fornitore AIS esterno. Non in v1; il protocollo è già pronto ad accoglierlo.
    case ais

    public var label: String {
        switch self {
        case .device: String(localized: "GPS del telefono", comment: "Provenienza della posizione")
        case .schedule: String(localized: "stimata dagli orari", comment: "Provenienza della posizione")
        case .ais: String(localized: "AIS", comment: "Provenienza della posizione")
        }
    }

    /// Vero se la posizione è misurata e non dedotta.
    public var isMeasured: Bool { self != .schedule }
}

/// Quanto è vecchio un dato.
///
/// Categorie e non secondi grezzi, così ogni schermata decide allo stesso modo se
/// mostrare un dato come vivo o come da prendere con le pinze.
public enum Freshness: Equatable, Sendable {
    case live
    case recent(TimeInterval)
    case stale(TimeInterval)

    public static let recentThreshold: TimeInterval = 120
    public static let staleThreshold: TimeInterval = 900

    public static func of(_ timestamp: Date, at now: Date) -> Freshness {
        let age = max(0, now.timeIntervalSince(timestamp))
        if age < recentThreshold { return .live }
        if age < staleThreshold { return .recent(age) }
        return .stale(age)
    }

    public var age: TimeInterval {
        switch self {
        case .live: 0
        case .recent(let a), .stale(let a): a
        }
    }

    /// Vero quando il dato va accompagnato da un avviso esplicito.
    public var needsCaveat: Bool {
        if case .stale = self { return true }
        return false
    }

    /// "ora", "4 min fa", "19 min fa".
    public var label: String {
        switch self {
        case .live:
            return String(localized: "ora", comment: "Età di un dato appena aggiornato")
        case .recent(let a), .stale(let a):
            let minutes = max(1, Int((a / 60).rounded()))
            return String(localized: "\(minutes) min fa", comment: "Età di un dato in minuti")
        }
    }
}

/// Una posizione della nave, con l'ora e la provenienza attaccate.
public struct ShipFix: Equatable, Sendable, Codable {
    public var coordinate: Coordinate
    public var timestamp: Date
    /// Rotta sul fondo in gradi veri, se nota.
    public var course: Double?
    /// Velocità sul fondo in nodi, se nota.
    public var speed: Double?
    public var origin: PositionOrigin

    public init(coordinate: Coordinate, timestamp: Date,
                course: Double? = nil, speed: Double? = nil,
                origin: PositionOrigin) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.course = course
        self.speed = speed
        self.origin = origin
    }

    public func freshness(at now: Date) -> Freshness { .of(timestamp, at: now) }
}

/// Unità di velocità, scelta dall'utente.
public enum SpeedUnit: String, Codable, Sendable, CaseIterable {
    case knots, kilometresPerHour

    public var label: String {
        switch self {
        case .knots: String(localized: "nodi", comment: "Unità di velocità")
        case .kilometresPerHour: String(localized: "km/h", comment: "Unità di velocità")
        }
    }

    public var suffix: String {
        switch self {
        case .knots: "kt"
        case .kilometresPerHour: "km/h"
        }
    }

    /// Converte da nodi, che è come i dati arrivano.
    public func value(fromKnots knots: Double) -> Double {
        switch self {
        case .knots: knots
        case .kilometresPerHour: knots * 1.852
        }
    }
}
