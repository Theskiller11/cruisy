import Testing
import Foundation
@testable import Cruisy

@Suite("La pagina di una crociera")
struct LoggedVoyageStoryTests {

    private let day = 86_400.0
    private let start = Date(timeIntervalSince1970: 1_763_164_800)  // 15 nov 2025, 00:00 UTC
    private let civitavecchia = Coordinate(latitude: 42.09, longitude: 11.79)
    private let barcellona = Coordinate(latitude: 41.36, longitude: 2.19)
    private let palma = Coordinate(latitude: 39.57, longitude: 2.65)

    /// Civitavecchia, un giorno di mare, Barcellona, Palma il giorno dopo.
    private func entry(track: Track? = nil) -> LoggedVoyage {
        LoggedVoyage(
            id: UUID(), shipName: "Stella Polare",
            ports: [
                LoggedPort(name: "Civitavecchia", region: "Italia", coordinate: civitavecchia,
                           arrival: start + 8 * 3600),
                LoggedPort(name: "Barcellona", region: "Spagna", coordinate: barcellona,
                           arrival: start + 2 * day + 8 * 3600),
                LoggedPort(name: "Palma", region: "Spagna", coordinate: palma,
                           arrival: start + 3 * day + 8 * 3600),
            ],
            nauticalMiles: 0, seaDays: 1, track: track)
    }

    /// Una traccia che va dritta da un punto all'altro, un punto ogni dieci minuti.
    private func straightTrack(from a: Coordinate, to b: Coordinate, leaving: Date, arriving: Date) -> [TrackPoint] {
        let steps = Int(arriving.timeIntervalSince(leaving) / 600)
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            return TrackPoint(coordinate: Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                     longitude: a.longitude + (b.longitude - a.longitude) * t),
                              at: leaving + Double(step) * 600)
        }
    }

    @Test("Senza traccia ogni tratta è la corda fra i porti, e non si dice registrata")
    func legsWithoutTrack() {
        let legs = entry().legs(track: nil)
        #expect(legs.count == 2)
        #expect(legs.allSatisfy { !$0.isRecorded })
        #expect(abs(legs[0].nauticalMiles - Geo.nauticalMiles(from: civitavecchia, to: barcellona)) < 0.01)
    }

    @Test("Una tratta registrata usa la traccia, e non è mai più corta della corda")
    func recordedLeg() {
        let points = straightTrack(from: civitavecchia, to: barcellona,
                                   leaving: start + 10 * 3600, arriving: start + 2 * day + 6 * 3600)
        let legs = entry().legs(track: Track(points: points))
        #expect(legs[0].isRecorded)
        #expect(legs[0].nauticalMiles >= Geo.nauticalMiles(from: civitavecchia, to: barcellona) - 0.01)
        #expect(!legs[1].isRecorded, "fra Barcellona e Palma non c'è traccia")
    }

    @Test("Le miglia di una traversata le dice il giorno di mare, non il porto d'arrivo")
    func milesShownOnce() {
        let days = entry().days(track: nil)
        #expect(days.count == 4)
        guard case .port(let first, let firstLeg) = days[0],
              case .sea(_, let seaLeg) = days[1],
              case .port(let second, let secondLeg) = days[2],
              case .port(_, let thirdLeg) = days[3]
        else { Issue.record("giorni nell'ordine sbagliato: \(days)"); return }
        #expect(first.name == "Civitavecchia" && firstLeg == nil)
        #expect(seaLeg?.to.name == "Barcellona")
        #expect(second.name == "Barcellona" && secondLeg == nil)
        #expect(thirdLeg?.to.name == "Palma", "da Barcellona a Palma non c'è mare in mezzo: le miglia vanno sul porto")
    }

    @Test("Una crociera in corso conta i giorni fino a oggi")
    func throughToday() {
        let days = entry().days(track: nil, through: start + 5 * day)
        #expect(days.count == 6)
        if case .sea(_, let leg) = days.last { #expect(leg == nil) } else { Issue.record("l'ultimo giorno dovrebbe essere di mare") }
    }

    @Test("Senza traccia la rotta è tutta tratteggiata")
    func sketchWithoutTrack() {
        let sketch = entry().routeSketch(track: nil)
        #expect(sketch.recorded.isEmpty)
        #expect(sketch.gaps.count == 2)
    }

    @Test("Un buco nella traccia diventa un tratto tratteggiato")
    func sketchWithGap() {
        let leaving = start + 10 * 3600
        var points = straightTrack(from: civitavecchia, to: barcellona,
                                   leaving: leaving, arriving: start + 2 * day + 6 * 3600)
        // Sei ore senza segnale a metà strada.
        let middle = points.count / 2
        points.removeSubrange(middle..<(middle + 36))
        let sketch = entry().routeSketch(track: Track(points: points))
        #expect(sketch.recorded.count == 2)
        // Il buco a metà, più la tratta Barcellona–Palma che non ha traccia.
        #expect(sketch.gaps.count == 2)
    }

    @Test("La velocità massima è su mezz'ora, e un salto del GPS non la gonfia")
    func topSpeed() throws {
        // Venti nodi: un terzo di miglio al minuto, un punto ogni dieci minuti.
        var points = (0..<12).map { step in
            TrackPoint(coordinate: Coordinate(latitude: 40 + Double(step) * (20.0 / 6) / 60, longitude: 5),
                       at: start + Double(step) * 600)
        }
        // Un punto sballato di cinque miglia: sommando i passi sembrerebbero 30 nodi.
        points[6].coordinate.longitude += 5.0 / 60 / cos(40 * .pi / 180)
        let speed = try #require(Track(points: points).topSpeed())
        #expect(speed.knots > 18 && speed.knots < 24)
    }

    @Test("Le notti vanno dal giorno d'imbarco a quello dell'ultimo scalo")
    func nights() {
        #expect(entry().nights == 3)
    }
}
