import Testing
import Foundation
@testable import Cruisy

@Suite("Ora di bordo")
struct ShipClockTests {

    @Test("Lo scarto si scrive come lo scriverebbe un ufficiale di bordo")
    func offsetLabels() {
        #expect(ShipClock.offsetLabel(secondsFromGMT: -4 * 3600) == "UTC−4")
        #expect(ShipClock.offsetLabel(secondsFromGMT: 2 * 3600) == "UTC+2")
        #expect(ShipClock.offsetLabel(secondsFromGMT: 5 * 3600 + 1800) == "UTC+5:30")
        #expect(ShipClock.offsetLabel(secondsFromGMT: 0) == "UTC+0")
    }

    @Test("Lo scarto del telefono è la differenza vera, col segno giusto")
    func deviceDrift() {
        let ship = ShipClock(secondsFromGMT: -4 * 3600)
        let rome = TimeZone(identifier: "Europe/Rome")!
        let summer = Date(timeIntervalSince1970: 1_756_000_000) // agosto: Roma è UTC+2

        // Il telefono a Roma è sei ore avanti rispetto a una nave sull'UTC−4.
        #expect(ship.deviceDrift(at: summer, device: rome) == 6 * 3600)
        #expect(ship.matchesDevice(at: summer, device: rome) == false)
    }

    @Test("Il telefono allineato non fa comparire nessun avviso")
    func alignedDeviceIsSilent() {
        let ship = ShipClock(secondsFromGMT: -4 * 3600)
        let sameZone = TimeZone(secondsFromGMT: -4 * 3600)!
        #expect(ship.matchesDevice(at: .now, device: sameZone))
    }

    @Test("L'ora di bordo non fa l'ora legale")
    func shipTimeIgnoresDaylightSaving() {
        // Una nave tiene il proprio orologio: non lo sposta perché un paese cambia
        // regola. Il fuso è fisso apposta, e va verificato che resti tale a cavallo
        // di un cambio d'ora europeo.
        let ship = ShipClock(secondsFromGMT: 2 * 3600)
        let beforeChange = Date(timeIntervalSince1970: 1_761_000_000) // fine ottobre
        let afterChange = beforeChange.addingTimeInterval(7 * 86_400)

        #expect(ship.secondsFromGMT(at: beforeChange)
                == ship.secondsFromGMT(at: afterChange))
    }

    @Test("L'inizio del giorno è la mezzanotte di bordo, non quella del telefono")
    func startOfDayFollowsTheShip() {
        let ship = ShipClock(secondsFromGMT: -4 * 3600)
        let instant = Date(timeIntervalSince1970: 1_756_000_000)
        let midnight = ship.startOfDay(for: instant)

        let calendar = ship.calendar(at: instant)
        #expect(calendar.component(.hour, from: midnight) == 0)
        #expect(midnight <= instant)
        #expect(instant.timeIntervalSince(midnight) < 86_400)
    }
}
