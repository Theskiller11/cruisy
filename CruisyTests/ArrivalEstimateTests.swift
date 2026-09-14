import Testing
import Foundation
@testable import Cruisy

@Suite("Stima dell'arrivo")
struct ArrivalEstimateTests {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    /// Un porto a `miles` miglia a est dell'origine, con l'arrivo pubblicato fra `hours`.
    private func port(milesEast miles: Double, arrivingIn hours: Double) -> PortCall {
        PortCall(name: "Destinazione", region: "",
                 coordinate: Coordinate(latitude: 0, longitude: miles / 60),
                 arrival: now.addingTimeInterval(hours * 3600))
    }

    /// Una traccia verso est a `knots` nodi, per `hours` ore fino ad adesso.
    private func track(knots: Double, hours: Double, endingMinutesAgo: Double = 0) -> Track {
        var track = Track()
        let end = now.addingTimeInterval(-endingMinutesAgo * 60)
        let start = end.addingTimeInterval(-hours * 3600)
        var t = start
        while t <= end {
            let elapsed = t.timeIntervalSince(start) / 3600
            // Si parte da −(knots × hours) miglia, così l'ultimo punto è all'origine.
            let miles = knots * (elapsed - hours)
            track.append(TrackPoint(coordinate: Coordinate(latitude: 0, longitude: miles / 60), at: t))
            t.addTimeInterval(5 * 60)
        }
        return track
    }

    @Test("Una nave in orario non fa scattare nessun avviso")
    func onScheduleIsQuiet() throws {
        // 20 nodi, 100 miglia: cinque ore, e l'arrivo pubblicato è fra cinque ore.
        let estimate = try #require(ArrivalEstimate.estimate(
            track: track(knots: 20, hours: 3), destination: port(milesEast: 100, arrivingIn: 5), now: now))
        #expect(abs(estimate.averageKnots - 20) < 0.5)
        #expect(abs(estimate.delay) < 10 * 60)
        #expect(estimate.isLate == false)
    }

    @Test("Una nave troppo lenta risulta in ritardo")
    func slowShipIsLate() throws {
        // 12 nodi per 100 miglia fanno otto ore e venti, contro cinque pubblicate.
        let estimate = try #require(ArrivalEstimate.estimate(
            track: track(knots: 12, hours: 3), destination: port(milesEast: 100, arrivingIn: 5), now: now))
        #expect(estimate.isLate)
        #expect(estimate.delay > 3 * 3600)
    }

    @Test("Un anticipo non è un ritardo")
    func earlyIsNotLate() throws {
        let estimate = try #require(ArrivalEstimate.estimate(
            track: track(knots: 25, hours: 3), destination: port(milesEast: 100, arrivingIn: 8), now: now))
        #expect(estimate.delay < 0)
        #expect(estimate.isLate == false)
    }

    @Test("Con meno di un'ora e mezza di traccia non si stima")
    func shortTrackIsNotEnough() {
        #expect(ArrivalEstimate.estimate(
            track: track(knots: 12, hours: 1), destination: port(milesEast: 100, arrivingIn: 5), now: now) == nil)
    }

    @Test("A più di dodici ore dall'arrivo non si stima")
    func tooFarAheadIsNotEstimated() {
        // Una nave che di notte va piano per risparmiare carburante sembrerebbe in
        // ritardo di ore senza esserlo.
        #expect(ArrivalEstimate.estimate(
            track: track(knots: 10, hours: 3), destination: port(milesEast: 300, arrivingIn: 20), now: now) == nil)
    }

    @Test("Una traccia ferma da tempo non dice dove si è adesso")
    func staleTrackIsIgnored() {
        #expect(ArrivalEstimate.estimate(
            track: track(knots: 12, hours: 3, endingMinutesAgo: 45),
            destination: port(milesEast: 100, arrivingIn: 5), now: now) == nil)
    }

    @Test("Una nave ferma non produce ritardi di giorni")
    func stoppedShipIsNotEstimated() {
        #expect(ArrivalEstimate.estimate(
            track: track(knots: 0.5, hours: 3), destination: port(milesEast: 100, arrivingIn: 5), now: now) == nil)
    }

    @Test("Ad arrivo passato non si stima")
    func pastArrivalIsIgnored() {
        #expect(ArrivalEstimate.estimate(
            track: track(knots: 12, hours: 3), destination: port(milesEast: 10, arrivingIn: -1), now: now) == nil)
    }
}
