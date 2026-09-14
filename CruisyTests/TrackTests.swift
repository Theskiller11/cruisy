import Testing
import Foundation
@testable import Cruisy

@Suite("Rotta percorsa")
struct TrackTests {

    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// Un punto a `minuti` dall'inizio, spostato di `miglia` verso est.
    private func point(_ minutes: Double, milesEast miles: Double) -> TrackPoint {
        // Un grado di longitudine all'equatore è 60 miglia nautiche.
        TrackPoint(coordinate: Coordinate(latitude: 0, longitude: miles / 60),
                   at: start.addingTimeInterval(minutes * 60))
    }

    @Test("Il primo punto entra sempre")
    func firstPointAlwaysLands() {
        var track = Track()
        let entrato = track.append(point(0, milesEast: 0))
        #expect(entrato)
        #expect(track.points.count == 1)
    }

    @Test("Una nave ferma in banchina non riempie la traccia di rumore")
    func stationaryShipDoesNotAccumulate() {
        // Il GPS in porto oscilla di qualche decina di metri. Senza il filtro,
        // nove ore di sosta disegnerebbero un gomitolo e gonfierebbero le miglia.
        var track = Track()
        track.append(point(0, milesEast: 0))
        for minute in stride(from: 5.0, through: 540, by: 5) {
            let jitter = (minute.truncatingRemainder(dividingBy: 2) == 0 ? 0.02 : -0.02)
            track.append(point(minute, milesEast: jitter))
        }
        #expect(track.points.count == 1, "sono entrati \(track.points.count) punti di rumore")
        #expect(track.nauticalMiles == 0)
    }

    @Test("Una nave che naviga lascia un punto ogni due minuti, non di più")
    func sailingShipIsSampledOnce() {
        // Venti nodi: un terzo di miglio al minuto, quindi la distanza non è mai il
        // vincolo — a fermare il conteggio è l'intervallo minimo.
        var track = Track()
        for minute in stride(from: 0.0, through: 60, by: 0.5) {
            track.append(point(minute, milesEast: minute / 3))
        }
        // 60 minuti / 2 = 30 intervalli, più il punto di partenza.
        #expect(track.points.count == 31, "punti: \(track.points.count)")
    }

    @Test("Un punto col timestamp all'indietro viene rifiutato")
    func outOfOrderPointsAreRejected() {
        var track = Track()
        track.append(point(10, milesEast: 0))
        let indietro = track.append(point(5, milesEast: 10))
        #expect(indietro == false)
        #expect(track.points.count == 1)
    }

    @Test("Le miglia sono la somma dei tratti")
    func milesAddUp() {
        var track = Track()
        for minute in stride(from: 0.0, through: 100, by: 10) {
            track.append(point(minute, milesEast: minute))
        }
        #expect(abs(track.nauticalMiles - 100) < 0.5, "\(track.nauticalMiles)")
    }

    @Test("Le miglia vere sono più delle miglia in linea retta")
    func realMilesExceedTheStraightLine() {
        // Una rotta che gira attorno a qualcosa: partenza e arrivo vicini, strada
        // lunga. È il motivo per cui la traccia esiste — le corde fra i porti danno
        // sempre un numero per difetto.
        var track = Track()
        var minute = 0.0
        for step in 0..<12 {
            let angle = Double(step) / 12 * 2 * .pi
            track.append(TrackPoint(
                coordinate: Coordinate(latitude: sin(angle) * 0.5, longitude: cos(angle) * 0.5),
                at: start.addingTimeInterval(minute * 60)))
            minute += 30
        }
        let corda = Geo.nauticalMiles(from: track.points.first!.coordinate,
                                      to: track.points.last!.coordinate)
        #expect(track.nauticalMiles > corda * 3)
    }

    // MARK: Alleggerimento

    @Test("Una linea dritta si riduce ai due estremi")
    func straightLineCollapses() {
        var track = Track()
        for minute in stride(from: 0.0, through: 200, by: 10) {
            track.append(point(minute, milesEast: minute))
        }
        #expect(track.points.count == 21)
        #expect(track.simplified().points.count == 2)
    }

    @Test("Alleggerire tiene la forma e le miglia")
    func simplifyingKeepsTheShape() {
        var track = Track()
        var minute = 0.0
        for step in 0..<200 {
            // Una rotta che curva davvero, con un po' di rumore sopra.
            let t = Double(step) / 200
            track.append(TrackPoint(
                coordinate: Coordinate(latitude: sin(t * .pi) * 3 + sin(t * 60) * 0.002,
                                       longitude: t * 8),
                at: start.addingTimeInterval(minute * 60)))
            minute += 10
        }
        let alleggerita = track.simplified()
        #expect(alleggerita.points.count < track.points.count / 3,
                "da \(track.points.count) a \(alleggerita.points.count)")
        #expect(alleggerita.points.first == track.points.first)
        #expect(alleggerita.points.last == track.points.last)
        // La forma regge: le miglia non devono cambiare di più del 5%.
        let scarto = abs(alleggerita.nauticalMiles - track.nauticalMiles) / track.nauticalMiles
        #expect(scarto < 0.05, "scarto \(scarto * 100)%")
    }

    @Test("Alleggerire una traccia corta non la tocca")
    func shortTracksSurvive() {
        var track = Track()
        track.append(point(0, milesEast: 0))
        track.append(point(10, milesEast: 5))
        #expect(track.simplified().points.count == 2)
    }

    @Test("Una traccia scritta e riletta è la stessa")
    func roundTrips() throws {
        var track = Track()
        for minute in stride(from: 0.0, through: 60, by: 3) {
            track.append(point(minute, milesEast: minute))
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Track.self, from: encoder.encode(track)) == track)
    }

    @Test("La finestra taglia quello che sta fuori")
    func clippingKeepsTheWindow() {
        var track = Track()
        for minute in stride(from: 0.0, through: 100, by: 10) {
            track.append(point(minute, milesEast: minute))
        }
        let taglio = track.clipped(from: start.addingTimeInterval(30 * 60),
                                   to: start.addingTimeInterval(60 * 60))
        #expect(taglio.points.count == 4)
    }
}
