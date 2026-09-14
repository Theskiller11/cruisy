import Testing
import Foundation
@testable import Cruisy

@Suite("Formattazione")
struct FormatTests {

    @Test("Le coordinate si scrivono in gradi e primi con l'emisfero giusto")
    func coordinates() {
        let caribbean = Coordinate(latitude: 19.4333, longitude: -68.2333)
        #expect(Format.latitude(caribbean) == "19°26'N")
        #expect(Format.longitude(caribbean) == "68°14'O")

        let southEast = Coordinate(latitude: -33.87, longitude: 151.21)
        #expect(Format.latitude(southEast).hasSuffix("S"))
        #expect(Format.longitude(southEast).hasSuffix("E"))
    }

    @Test("I primi arrotondati a sessanta passano al grado successivo")
    func minutesCarry() {
        // 19,9999° sono 19°59,99', che arrotondati fanno 60': va scritto 20°00', non 19°60'.
        let edge = Coordinate(latitude: 19.99999, longitude: 0)
        #expect(Format.latitude(edge) == "20°00'N")
    }

    @Test("Le durate si dicono come le direbbe una persona")
    func durations() {
        #expect(Format.duration(9 * 3600) == "9h")
        #expect(Format.duration(9 * 3600 + 30 * 60) == "9h 30")
        #expect(Format.duration(45 * 60) == "45 min")
    }

    @Test("La conversione di velocità è quella giusta")
    func speedConversion() {
        #expect(abs(SpeedUnit.knots.value(fromKnots: 18.4) - 18.4) < 1e-9)
        #expect(abs(SpeedUnit.kilometresPerHour.value(fromKnots: 18.4) - 34.0768) < 1e-4)
    }

    @Test("La freschezza di un dato cade nella categoria giusta")
    func freshness() {
        let now = Date()
        #expect(Freshness.of(now, at: now) == .live)
        #expect(Freshness.of(now.addingTimeInterval(-60), at: now) == .live)

        if case .recent = Freshness.of(now.addingTimeInterval(-300), at: now) {} else {
            Issue.record("Cinque minuti sono un dato recente")
        }
        let old = Freshness.of(now.addingTimeInterval(-1200), at: now)
        #expect(old.needsCaveat)
    }

    @Test("Un dato futuro non ha un'età negativa")
    func freshnessNeverNegative() {
        let now = Date()
        #expect(Freshness.of(now.addingTimeInterval(120), at: now).age == 0)
    }
}
