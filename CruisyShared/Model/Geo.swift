import Foundation

/// Una posizione sulla Terra. Tipo proprio invece di `CLLocationCoordinate2D`
/// perché deve essere `Codable`, condivisibile col widget e testabile senza CoreLocation.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Geometria sulla sfera. Serve per la distanza alla meta, il rilevamento della
/// prua e l'interpolazione della rotta quando la posizione viene dagli orari.
public enum Geo {

    /// Raggio medio terrestre in metri.
    public static let earthRadius = 6_371_008.8
    public static let metresPerNauticalMile = 1_852.0

    /// Distanza in metri lungo il cerchio massimo (formula dell'emisenoverso).
    public static func distance(from a: Coordinate, to b: Coordinate) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let dφ = (b.latitude - a.latitude) * .pi / 180
        let dλ = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Distanza in miglia nautiche, l'unità in cui si ragiona in mare.
    public static func nauticalMiles(from a: Coordinate, to b: Coordinate) -> Double {
        distance(from: a, to: b) / metresPerNauticalMile
    }

    /// Rotta iniziale da `a` a `b`, in gradi da 0 a 360 rispetto al nord vero.
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let dλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Punto intermedio lungo il cerchio massimo, con `fraction` da 0 a 1.
    /// Interpolazione sferica: su una traversata caraibica l'errore rispetto a una
    /// lineare in lat/lon è di miglia, non di metri.
    public static func interpolate(from a: Coordinate, to b: Coordinate, fraction: Double) -> Coordinate {
        let f = min(max(fraction, 0), 1)
        let φ1 = a.latitude * .pi / 180, λ1 = a.longitude * .pi / 180
        let φ2 = b.latitude * .pi / 180, λ2 = b.longitude * .pi / 180
        let δ = distance(from: a, to: b) / earthRadius
        guard δ > 1e-12 else { return a }

        let A = sin((1 - f) * δ) / sin(δ)
        let B = sin(f * δ) / sin(δ)
        let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
        let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
        let z = A * sin(φ1) + B * sin(φ2)
        return Coordinate(latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
                          longitude: atan2(y, x) * 180 / .pi)
    }

    /// Il punto cardinale a 8 settori, per dire "O/NO" accanto ai gradi.
    public static func compassPoint(_ degrees: Double) -> String {
        // I punti si compongono dalle quattro iniziali invece di elencare sedici
        // stringhe: fra italiano e inglese cambia solo l'ovest (O → W), e sedici
        // traduzioni per una lettera sarebbero sedici occasioni di sbagliare.
        let n = String(localized: "N", comment: "Punto cardinale: nord")
        let e = String(localized: "E", comment: "Punto cardinale: est")
        let s = String(localized: "S", comment: "Punto cardinale: sud")
        let w = String(localized: "O", comment: "Punto cardinale: ovest (west)")
        let names = [n, "\(n)/\(n)\(e)", "\(n)\(e)", "\(e)/\(n)\(e)",
                     e, "\(e)/\(s)\(e)", "\(s)\(e)", "\(s)/\(s)\(e)",
                     s, "\(s)/\(s)\(w)", "\(s)\(w)", "\(w)/\(s)\(w)",
                     w, "\(w)/\(n)\(w)", "\(n)\(w)", "\(n)/\(n)\(w)"]
        let normalised = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return names[Int((normalised / 22.5).rounded()) % 16]
    }
}
