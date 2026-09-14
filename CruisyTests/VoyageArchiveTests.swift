import Testing
import Foundation
@testable import Cruisy

/// Il giro completo salva → rileggi.
///
/// È il contratto da cui dipende il widget: gira in un altro processo e l'unica cosa
/// che condivide con l'app è questo file. Se la codifica delle date o il contenitore
/// cambiassero, il widget mostrerebbe "Nessuna crociera" senza che nulla si rompa in
/// modo visibile — il tipo di guasto che si scopre tardi e solo dal telefono di
/// qualcun altro.
@Suite("Archivio della crociera", .serialized)
struct VoyageArchiveTests {

    private let clock = ShipClock(secondsFromGMT: -4 * 3600)
    private let base = Date(timeIntervalSince1970: 1_756_000_000)

    private func sample() -> Voyage {
        Voyage(shipName: "Prova archivio", mmsi: "247000000", imo: "9000001", clock: clock, calls: [
            PortCall(name: "Partenza", region: "A",
                     coordinate: Coordinate(latitude: 18.47, longitude: -66.11),
                     role: .embarkation,
                     arrival: base, departure: base.addingTimeInterval(6 * 3600),
                     allAboard: base.addingTimeInterval(5 * 3600),
                     berth: Berth(kind: .dock, name: "Molo 2")),
            PortCall(name: "Arrivo", region: "B",
                     coordinate: Coordinate(latitude: 25.77, longitude: -80.19),
                     role: .disembarkation,
                     arrival: base.addingTimeInterval(60 * 3600),
                     berth: Berth(kind: .tender),
                     scheduleOrigin: .userEdited),
        ])
    }

    @Test("Una crociera salvata torna indietro identica")
    func roundTrip() throws {
        let original = sample()
        defer { try? VoyageArchive.save(nil) }

        try VoyageArchive.save(original)
        let reloaded = try #require(VoyageArchive.load())

        #expect(reloaded == original)
    }

    @Test("Gli istanti sopravvivono al giro senza scivolare")
    func datesSurvive() throws {
        let original = sample()
        defer { try? VoyageArchive.save(nil) }

        try VoyageArchive.save(original)
        let reloaded = try #require(VoyageArchive.load())

        // Un secondo di scarto qui vorrebbe dire un countdown sbagliato di un secondo
        // per tutta la crociera, e nessuno se ne accorgerebbe guardando.
        for (a, b) in zip(original.calls, reloaded.calls) {
            #expect(abs(a.arrival.timeIntervalSince(b.arrival)) < 0.001)
            #expect(a.allAboard?.timeIntervalSince1970 == b.allAboard?.timeIntervalSince1970)
            #expect(a.departure?.timeIntervalSince1970 == b.departure?.timeIntervalSince1970)
        }
        #expect(reloaded.clock == original.clock)
    }

    @Test("Le correzioni dell'utente non si perdono per strada")
    func originSurvives() throws {
        defer { try? VoyageArchive.save(nil) }
        try VoyageArchive.save(sample())
        let reloaded = try #require(VoyageArchive.load())
        // Se questo campo si perdesse, un orario corretto a bordo tornerebbe a
        // presentarsi come "orario pubblicato" e la provenienza mentirebbe.
        #expect(reloaded.calls.last?.scheduleOrigin == .userEdited)
        #expect(reloaded.calls.last?.berth.kind == .tender)
    }

    @Test("Cancellare svuota davvero l'archivio")
    func clearing() throws {
        try VoyageArchive.save(sample())
        #expect(VoyageArchive.load() != nil)
        try VoyageArchive.save(nil)
        #expect(VoyageArchive.load() == nil)
    }
}
