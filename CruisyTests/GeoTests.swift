import Testing
import Foundation
@testable import Cruisy

@Suite("Geometria")
struct GeoTests {

    private let sanJuan = Coordinate(latitude: 18.4655, longitude: -66.1057)
    private let miami = Coordinate(latitude: 25.7743, longitude: -80.1937)

    @Test("La distanza corrisponde a quella nota fra due porti")
    func knownDistance() {
        // San Juan – Miami sono circa 900 miglia nautiche in linea d'aria.
        let miles = Geo.nauticalMiles(from: sanJuan, to: miami)
        #expect(miles > 850 && miles < 950)
    }

    @Test("La distanza è simmetrica e nulla su sé stessa")
    func distanceProperties() {
        #expect(Geo.distance(from: sanJuan, to: sanJuan) < 1e-6)
        let there = Geo.distance(from: sanJuan, to: miami)
        let back = Geo.distance(from: miami, to: sanJuan)
        #expect(abs(there - back) < 1e-6)
    }

    @Test("Il rilevamento sta sempre fra zero e 360")
    func bearingRange() {
        for lon in stride(from: -180.0, through: 180.0, by: 30) {
            let b = Geo.bearing(from: sanJuan, to: Coordinate(latitude: 10, longitude: lon))
            #expect(b >= 0 && b < 360)
        }
    }

    @Test("Da San Juan verso Miami si punta a ponente")
    func bearingDirection() {
        let b = Geo.bearing(from: sanJuan, to: miami)
        #expect(b > 270 && b < 320)      // fra ovest e nordovest
        // Il punto si confronta con la lettera **tradotta**, non con "O": in
        // inglese l'ovest è "W", e un test che fissa la lingua fallisce appena
        // l'app ne parla una seconda.
        #expect(Geo.compassPoint(b).contains(String(localized: "O")))
    }

    @Test("L'interpolazione parte, arriva, e a metà sta in mezzo")
    func interpolationEndpoints() {
        let start = Geo.interpolate(from: sanJuan, to: miami, fraction: 0)
        let end = Geo.interpolate(from: sanJuan, to: miami, fraction: 1)
        #expect(abs(start.latitude - sanJuan.latitude) < 1e-6)
        #expect(abs(end.longitude - miami.longitude) < 1e-6)

        let middle = Geo.interpolate(from: sanJuan, to: miami, fraction: 0.5)
        let toStart = Geo.distance(from: middle, to: sanJuan)
        let toEnd = Geo.distance(from: middle, to: miami)
        #expect(abs(toStart - toEnd) / toStart < 0.01)
    }

    @Test("Le frazioni fuori scala non escono dalla tratta")
    func interpolationClamped() {
        let before = Geo.interpolate(from: sanJuan, to: miami, fraction: -3)
        #expect(abs(before.latitude - sanJuan.latitude) < 1e-6)
        let after = Geo.interpolate(from: sanJuan, to: miami, fraction: 7)
        #expect(abs(after.latitude - miami.latitude) < 1e-6)
    }

    @Test("La rosa dei venti nomina i punti giusti")
    func compassPoints() {
        // Si verifica la geometria — quale quarto risponde a quali gradi — non
        // come si scrive: le iniziali cambiano con la lingua.
        let n = String(localized: "N"), e = String(localized: "E")
        let s = String(localized: "S"), w = String(localized: "O")
        #expect(Geo.compassPoint(0) == n)
        #expect(Geo.compassPoint(90) == e)
        #expect(Geo.compassPoint(180) == s)
        #expect(Geo.compassPoint(270) == w)
        #expect(Geo.compassPoint(359.9) == n)
        #expect(Geo.compassPoint(225) == "\(s)\(w)")
        // Le quattro iniziali devono restare distinte in ogni lingua, se no due
        // quarti opposti si scriverebbero uguale.
        #expect(Set([n, e, s, w]).count == 4)
    }
}
