import Testing
import Foundation
@testable import Cruisy

/// Il file `.cruisy`, che è il modo in cui una crociera passa da un telefono all'altro.
///
/// Sostituisce la sincronizzazione iCloud, che richiedeva una capability non
/// disponibile — e in crociera funziona meglio: AirDrop fra due telefoni sullo stesso
/// ponte non ha bisogno di rete.
@Suite("File della crociera")
struct VoyageFileTests {

    private let clock = ShipClock(secondsFromGMT: -4 * 3600)
    private let base = Date(timeIntervalSince1970: 1_756_000_000)

    /// **Una sola** istanza per test: `Voyage` e `PortCall` generano un `UUID` nuovo
    /// a ogni costruzione, quindi due crociere "uguali" costruite due volte non lo
    /// sono — ed è giusto così, l'identità fa parte del dato.
    private let sample: Voyage = {
        let clock = ShipClock(secondsFromGMT: -4 * 3600)
        let base = Date(timeIntervalSince1970: 1_756_000_000)
        return Voyage(shipName: "Stella Australe", mmsi: "247000000", imo: "9000001", clock: clock, calls: [
            PortCall(name: "San Juan", region: "Puerto Rico",
                     coordinate: Coordinate(latitude: 18.47, longitude: -66.11),
                     role: .embarkation, arrival: base,
                     departure: base.addingTimeInterval(6 * 3600),
                     allAboard: base.addingTimeInterval(5 * 3600),
                     berth: Berth(kind: .dock, name: "Molo 2")),
            PortCall(name: "Gustavia", region: "Saint-Barthélemy",
                     coordinate: Coordinate(latitude: 17.90, longitude: -62.85),
                     role: .port, arrival: base.addingTimeInterval(30 * 3600),
                     departure: base.addingTimeInterval(39 * 3600),
                     allAboard: base.addingTimeInterval(38 * 3600),
                     berth: Berth(kind: .tender), scheduleOrigin: .userEdited),
            PortCall(name: "Miami", region: "United States",
                     coordinate: Coordinate(latitude: 25.77, longitude: -80.19),
                     role: .disembarkation, arrival: base.addingTimeInterval(60 * 3600)),
        ], updatedAt: base)
    }()

    @Test("Una crociera scritta su file torna indietro identica")
    func roundTrip() throws {
        let original = sample
        let restored = try VoyageFile.voyage(from: VoyageFile.data(for: original))
        #expect(restored == original)
    }

    @Test("Le correzioni fatte a bordo sopravvivono al passaggio")
    func correctionsSurvive() throws {
        let restored = try VoyageFile.voyage(from: VoyageFile.data(for: sample))
        // Se questo campo si perdesse, un orario corretto a bordo si ripresenterebbe
        // come "orario pubblicato" a chi riceve il file, e la provenienza mentirebbe.
        #expect(restored.calls[1].scheduleOrigin == .userEdited)
        #expect(restored.calls[1].berth.kind == .tender)
        #expect(restored.clock == sample.clock)
    }

    @Test("Gli istanti non scivolano di un secondo")
    func instantsAreExact() throws {
        let original = sample
        let restored = try VoyageFile.voyage(from: VoyageFile.data(for: original))
        for (a, b) in zip(original.calls, restored.calls) {
            #expect(a.arrival.timeIntervalSince1970 == b.arrival.timeIntervalSince1970)
            #expect(a.allAboard?.timeIntervalSince1970 == b.allAboard?.timeIntervalSince1970)
        }
    }

    @Test("Legge anche una crociera salvata senza involucro")
    func readsBareVoyage() throws {
        // È il formato del file interno dell'app: tollerarlo rende il tipo di
        // documento più facile da maneggiare a mano.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bare = try encoder.encode(sample)
        #expect(try VoyageFile.voyage(from: bare) == sample)
    }

    @Test("Un file che non è una crociera non passa per buono")
    func garbageIsRejected() {
        #expect(throws: (any Error).self) {
            try VoyageFile.voyage(from: Data("ciao come stai".utf8))
        }
    }

    @Test("Il nome del file si legge da solo e non rompe il percorso")
    func fileNameIsReadable() {
        let name = VoyageFile.fileName(for: sample)
        #expect(name.hasSuffix(".cruisy"))
        #expect(name.contains("Stella Australe"))
        #expect(!name.contains("/"))

        // Una nave con una barra nel nome non deve produrre un percorso valido.
        var odd = sample
        odd.shipName = "M/N Qualcosa"
        #expect(!VoyageFile.fileName(for: odd).contains("/"))
    }

    @Test("Scritto e riletto da disco")
    func writesToDisk() throws {
        let url = try VoyageFile.export(sample)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "cruisy")
        #expect(try VoyageFile.read(from: url) == sample)
    }
}
