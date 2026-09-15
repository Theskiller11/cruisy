import Testing
import Foundation
@testable import Cruisy

@Suite("Diario di bordo")
struct LogbookTests {

    /// Una crociera di prova: tre scali, un giorno di mare in mezzo.
    private func voyage(id: UUID = UUID()) -> Voyage {
        let day = 86_400.0
        let start = Date(timeIntervalSince1970: 1_763_164_800)  // 15 nov 2025, 00:00 UTC
        return Voyage(
            id: id, shipName: "Explora I",
            clock: ShipClock(secondsFromGMT: 3600),
            calls: [
                PortCall(name: "Civitavecchia", region: "Italia",
                         coordinate: Coordinate(latitude: 42.09, longitude: 11.79),
                         role: .embarkation, arrival: start,
                         departure: start + 6 * 3600, allAboard: start + 5 * 3600),
                // due giorni dopo: in mezzo c'è una giornata senza scali
                PortCall(name: "Barcellona", region: "Spagna",
                         coordinate: Coordinate(latitude: 41.36, longitude: 2.19),
                         role: .port, arrival: start + 2 * day,
                         departure: start + 2 * day + 8 * 3600,
                         allAboard: start + 2 * day + 7 * 3600),
                PortCall(name: "Palma", region: "Spagna",
                         coordinate: Coordinate(latitude: 39.57, longitude: 2.65),
                         role: .disembarkation, arrival: start + 3 * day,
                         departure: nil, allAboard: nil),
            ])
    }

    @Test("Nel diario finisce solo quello che è già successo")
    func onlyThePast() {
        let voyage = voyage()
        let afterFirst = voyage.calls[0].arrival.addingTimeInterval(3600)
        let entry = LoggedVoyage.sailed(voyage, upTo: afterFirst)

        #expect(entry.ports.count == 1)
        #expect(entry.ports.first?.name == "Civitavecchia")
        // Un solo porto: nessun tratto percorso, quindi zero miglia.
        #expect(entry.nauticalMiles == 0)
    }

    @Test("Le miglia sommano i tratti fra gli scali toccati")
    func milesAccumulate() throws {
        let voyage = voyage()
        let entry = LoggedVoyage.sailed(voyage, upTo: .distantFuture)

        let leg1 = Geo.nauticalMiles(from: voyage.calls[0].coordinate, to: voyage.calls[1].coordinate)
        let leg2 = Geo.nauticalMiles(from: voyage.calls[1].coordinate, to: voyage.calls[2].coordinate)
        #expect(abs(entry.nauticalMiles - (leg1 + leg2)) < 0.01)
        // Civitavecchia–Barcellona è dell'ordine delle 400 miglia: se il conto fosse
        // in chilometri o in metri se ne accorgerebbe subito.
        #expect(entry.nauticalMiles > 400 && entry.nauticalMiles < 700)
    }

    @Test("Un giorno di mare è un giorno senza scali")
    func seaDays() {
        let entry = LoggedVoyage.sailed(voyage(), upTo: .distantFuture)
        // 15, 16, 17, 18 novembre: quattro giorni, tre con uno scalo.
        #expect(entry.seaDays == 1)
    }

    @Test("Il giorno di mare in corso si conta già")
    func seaDayInProgress() {
        let voyage = voyage()
        // Il giorno dopo il secondo scalo, in mezzo alla traversata verso il terzo.
        let underway = voyage.calls[1].arrival.addingTimeInterval(20 * 3600)
        let entry = LoggedVoyage.sailed(voyage, upTo: underway)

        #expect(entry.ports.count == 2)
        // 15 e 17 novembre a terra, il 16 in mare: uno.
        #expect(entry.seaDays == 1)
    }

    @Test("Riarchiviare la stessa crociera la aggiorna, non la duplica")
    func upsert() {
        let id = UUID()
        var logbook = Logbook()
        logbook.record(LoggedVoyage.sailed(voyage(id: id), upTo: voyage(id: id).calls[0].arrival))
        logbook.record(LoggedVoyage.sailed(voyage(id: id), upTo: .distantFuture))

        #expect(logbook.voyages.count == 1)
        #expect(logbook.voyages[0].ports.count == 3)
    }

    @Test("Una crociera senza porti raggiunti non entra nel diario")
    func nothingYet() {
        var logbook = Logbook()
        logbook.record(LoggedVoyage.sailed(voyage(), upTo: .distantPast))
        #expect(logbook.isEmpty)
    }

    @Test("I timbri contano le visite e tengono la prima volta")
    func stamps() throws {
        var logbook = Logbook()
        logbook.record(LoggedVoyage.sailed(voyage(), upTo: .distantFuture))
        // Una seconda crociera che ripassa da Barcellona, un anno dopo.
        var second = voyage(id: UUID())
        for index in second.calls.indices {
            second.calls[index].arrival += 365 * 86_400
        }
        logbook.record(LoggedVoyage.sailed(second, upTo: .distantFuture))

        #expect(logbook.voyages.count == 2)
        #expect(logbook.stamps.count == 3)
        let barcelona = try #require(logbook.stamps.first { $0.port.name == "Barcellona" })
        #expect(barcelona.visits == 2)
        // La prima volta è quella che resta.
        #expect(barcelona.port.arrival < second.calls[1].arrival)
    }

    @Test("I primati guardano tutte le crociere")
    func records() throws {
        var logbook = Logbook()
        logbook.record(LoggedVoyage.sailed(voyage(), upTo: .distantFuture))

        #expect(logbook.northernmost?.name == "Civitavecchia")
        #expect(logbook.southernmost?.name == "Palma")
        let crossing = try #require(logbook.longestCrossing)
        #expect(crossing.from.name == "Civitavecchia")
        #expect(crossing.to.name == "Barcellona")
        #expect(logbook.ships == ["Explora I"])
    }

    @Test("Il diario si rilegge dopo essere stato scritto")
    func roundTrip() throws {
        var logbook = Logbook()
        logbook.record(LoggedVoyage.sailed(voyage(), upTo: .distantFuture))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Logbook.self, from: encoder.encode(logbook))

        #expect(restored.voyages == logbook.voyages)
        #expect(restored.voyages[0].secondsFromGMT == 3600)
    }

    @Test("Un diario vecchio senza ora di bordo si legge lo stesso")
    func legacyDecoding() throws {
        let json = """
        {"voyages":[{"id":"\(UUID().uuidString)","shipName":"Explora I","ports":[],
        "nauticalMiles":10,"seaDays":1}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let logbook = try decoder.decode(Logbook.self, from: Data(json.utf8))
        #expect(logbook.voyages[0].secondsFromGMT == 0)
    }
}

@Suite("Il diario e l'archivio")
@MainActor
struct LogbookStoreTests {

    private func voyage() -> Voyage {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return Voyage(shipName: "Explora I", clock: ShipClock(secondsFromGMT: 0), calls: [
            PortCall(name: "Genova", region: "Italia",
                     coordinate: Coordinate(latitude: 44.41, longitude: 8.93),
                     role: .embarkation, arrival: start,
                     departure: start + 6 * 3600, allAboard: start + 5 * 3600),
            PortCall(name: "Napoli", region: "Italia",
                     coordinate: Coordinate(latitude: 40.84, longitude: 14.25),
                     role: .disembarkation, arrival: start + 86_400,
                     departure: nil, allAboard: nil),
        ])
    }

    @Test("Una crociera inserita a mano entra nel diario appena tocca un porto")
    func recordsRealVoyages() {
        let store = VoyageStore(voyage: nil, now: Date(timeIntervalSince1970: 1_700_000_100),
                                autoload: false)
        store.replace(with: voyage())
        #expect(store.logbook.logbook.voyages.count == 1)
        #expect(store.logbook.logbook.stamps.contains { $0.port.name == "Genova" })
    }

    @Test("Togliere una crociera la fa sparire dai totali")
    func forget() throws {
        let store = VoyageStore(voyage: nil, now: Date(timeIntervalSince1970: 1_700_000_100),
                                autoload: false)
        store.replace(with: voyage())
        let entry = try #require(store.logbook.logbook.voyages.first)
        store.logbook.forget(entry)
        #expect(store.logbook.logbook.isEmpty)
        #expect(store.logbook.logbook.nauticalMiles == 0)
    }
}
