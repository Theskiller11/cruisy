import Testing
import Foundation
@testable import Cruisy

@Suite("Countdown")
struct CountdownTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func countdown(hours: Double) -> Countdown {
        Countdown(start: start, target: start.addingTimeInterval(hours * 3600),
                  origin: .publishedSchedule)
    }

    @Test("Il tempo residuo non va mai sotto zero")
    func remainingNeverNegative() {
        let c = countdown(hours: 2)
        #expect(c.remaining(at: start) == 7200)
        #expect(c.remaining(at: c.target) == 0)
        // Dopo il traguardo: zero, non un numero negativo che si stamperebbe come
        // un countdown alla rovescia.
        #expect(c.remaining(at: c.target.addingTimeInterval(9999)) == 0)
    }

    @Test("Il progresso resta fra zero e uno")
    func progressClamped() {
        let c = countdown(hours: 4)
        #expect(c.progress(at: start) == 0)
        #expect(abs(c.progress(at: start.addingTimeInterval(7200)) - 0.5) < 1e-9)
        #expect(c.progress(at: c.target) == 1)
        #expect(c.progress(at: start.addingTimeInterval(-5000)) == 0)
        #expect(c.progress(at: c.target.addingTimeInterval(5000)) == 1)
    }

    @Test("Un intervallo rovesciato viene raddrizzato invece di produrre progressi negativi")
    func invertedRangeIsRepaired() {
        let c = Countdown(start: start.addingTimeInterval(3600), target: start, origin: .estimated)
        #expect(c.start <= c.target)
        #expect(c.progress(at: start) >= 0)
        #expect(c.progress(at: start) <= 1)
    }

    @Test("La formattazione mostra le ore solo quando ci sono")
    func formatting() {
        #expect(countdown(hours: 2.5).formatted(at: start) == "2:30:00")
        let underAnHour = Countdown(start: start, target: start.addingTimeInterval(605),
                                    origin: .publishedSchedule)
        #expect(underAnHour.formatted(at: start) == "10:05")
    }

    @Test("Le componenti sommano al tempo residuo")
    func componentsAreConsistent() {
        let c = Countdown(start: start, target: start.addingTimeInterval(3 * 3600 + 27 * 60 + 9),
                          origin: .publishedSchedule)
        let parts = c.components(at: start)
        #expect(parts.hours == 3)
        #expect(parts.minutes == 27)
        #expect(parts.seconds == 9)
    }

    @Test("L'imminenza guarda la finestra, non il segno")
    func imminence() {
        let c = countdown(hours: 2)
        #expect(c.isImminent(at: start) == false)
        #expect(c.isImminent(at: start.addingTimeInterval(5400)) == true)
        // Passato il traguardo non è più imminente: è successo.
        #expect(c.isImminent(at: c.target) == false)
    }

    @Test("Ogni countdown dichiara da dove viene")
    func originIsAlwaysPresent() {
        #expect(CountdownOrigin.publishedSchedule.isAuthoritative)
        #expect(CountdownOrigin.userEdited.isAuthoritative)
        #expect(CountdownOrigin.estimated.isAuthoritative == false)
    }
}
