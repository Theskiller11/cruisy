import Testing
import Foundation
@testable import Cruisy

/// Le crociere salvate prima di ogni cambio di formato devono continuare a leggersi.
///
/// Ogni formato su disco — crociera, diario, traccia, navi imparate — ha qui un
/// esemplare **scritto a mano nella forma vecchia**, non prodotto dal codice di oggi:
/// se lo producesse il codice di oggi, il test direbbe solo che il codice è
/// d'accordo con sé stesso. L'itinerario l'ha digitato una persona, e perderlo a un
/// aggiornamento sarebbe imperdonabile.
///
/// Questa suite ha già pagato: scrivendola è saltato fuori che la rotta registrata
/// non finiva mai nel file del diario, perché l'elenco delle chiavi non la nominava.
@Suite("Compatibilità dei formati su disco")
struct PersistenceCompatibilityTests {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    // MARK: La crociera

    /// Una crociera come la scriveva la prima versione: un solo scarto d'orologio,
    /// niente fusi sugli scali, niente `updatedAt`, niente identificativi.
    private let firstFormatVoyage = """
    {"id":"6C1D0F7E-0000-4000-8000-000000000001","shipName":"Explora I",
     "clock":{"secondsFromGMT":-14400,"source":"portTimeZone"},
     "calls":[
      {"id":"6C1D0F7E-0000-4000-8000-000000000010","name":"San Juan","region":"Porto Rico",
       "coordinate":{"latitude":18.4655,"longitude":-66.1057},"role":"embarkation",
       "arrival":"2026-11-15T18:00:00Z","departure":"2026-11-16T00:00:00Z",
       "allAboard":"2026-11-15T23:00:00Z","berth":{"kind":"dock"},"scheduleOrigin":"publishedSchedule"},
      {"id":"6C1D0F7E-0000-4000-8000-000000000011","name":"Gustavia","region":"Saint-Barthélemy",
       "coordinate":{"latitude":17.8962,"longitude":-62.8498},"role":"port",
       "arrival":"2026-11-17T12:00:00Z","departure":"2026-11-17T22:00:00Z",
       "allAboard":"2026-11-17T21:00:00Z","berth":{"kind":"tender"},"scheduleOrigin":"userEdited"},
      {"id":"6C1D0F7E-0000-4000-8000-000000000012","name":"Miami","region":"Florida",
       "coordinate":{"latitude":25.7743,"longitude":-80.1937},"role":"disembarkation",
       "arrival":"2026-11-22T12:00:00Z","berth":{"kind":"dock"},"scheduleOrigin":"publishedSchedule"}
     ]}
    """

    @Test("Una crociera del primo formato si legge, con l'orologio a scarto unico")
    func firstFormatVoyageDecodes() throws {
        let voyage = try decoder.decode(Voyage.self, from: Data(firstFormatVoyage.utf8))
        #expect(voyage.shipName == "Explora I")
        #expect(voyage.calls.count == 3)
        #expect(voyage.clock.secondsFromGMT(at: .distantPast) == -4 * 3600)
        #expect(voyage.clock.changes.count == 1)
        // I campi arrivati dopo restano vuoti, non inventati.
        #expect(voyage.updatedAt == nil)
        #expect(voyage.mmsi == nil && voyage.imo == nil)
        #expect(voyage.calls.allSatisfy { $0.timeZoneIdentifier == nil })
        // E quello che c'era non si perde: correzioni e tender compresi.
        #expect(voyage.calls[1].scheduleOrigin == .userEdited)
        #expect(voyage.calls[1].berth.kind == .tender)
        #expect(voyage.calls[1].allAboard == ISO8601DateFormatter().date(from: "2026-11-17T21:00:00Z"))
    }

    @Test("Riconciliata, una crociera vecchia prende i fusi e la scaletta dei cambi")
    func firstFormatVoyageReconciles() throws {
        let voyage = try decoder.decode(Voyage.self, from: Data(firstFormatVoyage.utf8))
        let reconciled = voyage.reconciled { call in
            ["San Juan": "America/Puerto_Rico", "Gustavia": "America/St_Barthelemy",
             "Miami": "America/New_York"][call.name]
        }
        #expect(reconciled.calls.allSatisfy { $0.timeZoneIdentifier != nil })
        // In novembre Miami è a UTC−5 e i Caraibi a UTC−4: il cambio compare da solo.
        #expect(reconciled.clock.changes.count >= 2)
        #expect(reconciled.clock.secondsFromGMT(at: reconciled.calls.last!.arrival) == -5 * 3600)
    }

    @Test("Una crociera di oggi scrive anche la forma vecchia dell'orologio")
    func currentVoyageKeepsLegacyClockKeys() throws {
        let clock = ShipClock(changes: [
            .init(at: .distantPast, secondsFromGMT: -4 * 3600, source: .portTimeZone),
            .init(at: Date(timeIntervalSince1970: 1_763_600_000), secondsFromGMT: -5 * 3600, source: .portTimeZone),
        ])
        let voyage = Voyage(shipName: "Prova", clock: clock, calls: [], updatedAt: Date(timeIntervalSince1970: 1_763_000_000))
        let data = try encoder.encode(voyage)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let clockObject = try #require(object["clock"] as? [String: Any])
        // Una versione precedente dell'app legge `secondsFromGMT` e ignora `changes`:
        // trova un orologio sensato invece di niente.
        #expect(clockObject["secondsFromGMT"] as? Int == -4 * 3600)
        #expect((clockObject["changes"] as? [Any])?.count == 2)

        let back = try decoder.decode(Voyage.self, from: data)
        #expect(back == voyage)
    }

    // MARK: Il diario

    @Test("La rotta registrata sopravvive nel file del diario")
    func logbookKeepsTheTrack() throws {
        let start = Date(timeIntervalSince1970: 1_763_000_000)
        let points = [
            TrackPoint(coordinate: Coordinate(latitude: 18.4, longitude: -66.1), at: start),
            TrackPoint(coordinate: Coordinate(latitude: 18.6, longitude: -65.5), at: start + 3600),
            TrackPoint(coordinate: Coordinate(latitude: 18.9, longitude: -64.9), at: start + 7200),
        ]
        var entry = LoggedVoyage(id: UUID(), shipName: "Prova", ports: [
            LoggedPort(name: "San Juan", region: "PR", coordinate: points[0].coordinate, arrival: start),
        ], nauticalMiles: 80, seaDays: 1, secondsFromGMT: -4 * 3600, track: Track(points: points))
        entry.nauticalMiles = entry.track!.nauticalMiles

        var logbook = Logbook()
        logbook.record(entry)
        let restored = try decoder.decode(Logbook.self, from: encoder.encode(logbook))
        let back = try #require(restored.voyages.first)
        #expect(back.track?.points.count == 3)
        #expect(back.track == entry.track)
        #expect(back.nauticalMiles == entry.nauticalMiles)
    }

    @Test("Un diario scritto senza rotta si legge, e la rotta resta assente")
    func logbookWithoutTrackDecodes() throws {
        let json = """
        {"voyages":[{"id":"6C1D0F7E-0000-4000-8000-000000000002","shipName":"Explora I",
          "ports":[{"name":"Genova","region":"Italia","coordinate":{"latitude":44.41,"longitude":8.93},
                    "arrival":"2025-11-15T00:00:00Z"}],
          "nauticalMiles":312.5,"seaDays":2,"secondsFromGMT":3600}]}
        """
        let logbook = try decoder.decode(Logbook.self, from: Data(json.utf8))
        let entry = try #require(logbook.voyages.first)
        #expect(entry.track == nil)
        #expect(entry.nauticalMiles == 312.5)
        #expect(entry.secondsFromGMT == 3600)
        #expect(entry.ports.first?.name == "Genova")
    }

    // MARK: La traccia

    @Test("Il file della traccia si rilegge com'era scritto")
    func trackFileDecodes() throws {
        let json = """
        {"points":[
          {"coordinate":{"latitude":18.4655,"longitude":-66.1057},"at":"2026-11-16T00:10:00Z"},
          {"coordinate":{"latitude":18.5100,"longitude":-65.9000},"at":"2026-11-16T00:40:00Z"}
        ]}
        """
        let track = try decoder.decode(Track.self, from: Data(json.utf8))
        #expect(track.points.count == 2)
        #expect(track.nauticalMiles > 10)
        #expect(track.first?.at == ISO8601DateFormatter().date(from: "2026-11-16T00:10:00Z"))
    }

    // MARK: Le navi imparate

    @Test("Le navi imparate a bordo si rileggono nella forma su disco")
    func learnedShipsDecode() throws {
        let json = """
        {"explora iii":{"name":"Explora III","imo":"9869899","mmsi":"","tonnage":73904,
          "length":268,"beam":0,"year":2026,"operatorName":"Explora Journeys","flag":"",
          "imageFile":""}}
        """
        struct Stored: Decodable {
            var name: String, imo: String, mmsi: String
            var tonnage: Double, length: Double, beam: Double
            var year: Int, operatorName: String, flag: String, imageFile: String
        }
        let stored = try JSONDecoder().decode([String: Stored].self, from: Data(json.utf8))
        let ship = try #require(stored["explora iii"])
        #expect(ship.name == "Explora III")
        #expect(ship.tonnage == 73904)
        #expect(ship.operatorName == "Explora Journeys")
    }
}
