import Testing
import Foundation
@testable import Cruisy

/// Le difese aggiunte il 23 settembre 2026 dopo i documenti di Explora: letture
/// storpiate dall'OCR, controlli di buon senso, due letture della stessa immagine,
/// la segnalazione di un problema.
@Suite("Affidabilità dell'importazione")
struct ImportReliabilityTests {

    private let parser = ItineraryTextParser()

    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: OCR storpiato

    @Test("Un porto con una lettera sbagliata si aggancia, da confermare")
    func misspelledPort() throws {
        let draft = parser.parse("""
        Nave: Explora III
        Ven 20 Nov  Puerto Plsta  09:00 - 17:00
        Sab 21 Nov  Grand Turk  08:00 - 17:00
        """)
        let call = try #require(draft.calls.first)
        #expect(call.port?.name == "Puerto Plata")
        #expect(call.issues.contains(.portUncertain), "un nome indovinato va sempre confermato")
    }

    @Test("Un nome che non somiglia a niente non si aggancia a caso")
    func gibberishStaysUnknown() {
        #expect(PortGazetteer.shared.fuzzyCandidates("Qwxzyk Bvvnm").isEmpty)
        #expect(PortGazetteer.shared.fuzzyCandidates("Fil Rouge").isEmpty)
    }

    @Test("«Parenza: 17.00» è una partenza")
    func misspelledLabel() throws {
        let draft = parser.parse("""
        Ven 20 Nov
        Puerto Plata
        Arrivo: 09:00
        • Parenza: 17.00
        """)
        let call = try #require(draft.calls.first)
        #expect(call.arrival == TimeOfDay(hour: 9, minute: 0))
        #expect(call.departure == TimeOfDay(hour: 17, minute: 0))
    }

    // MARK: Buon senso

    @Test("Un porto dall'altra parte del mondo il giorno dopo si segnala")
    func impossibleLeg() throws {
        // Da San Juan a Genova in una notte: nessuna nave ci arriva.
        let draft = parser.parse("""
        Nave: Explora III
        Dom 15 Nov  San Juan  imbarco 14:00 - partenza 20:00
        Lun 16 Nov  Genova  08:00 - 17:00
        """)
        #expect(draft.calls.contains { $0.issues.contains(.implausibleLeg) })
    }

    @Test("Una tappa vicina non si segnala")
    func plausibleLeg() {
        let draft = parser.parse("""
        Nave: Explora III
        Dom 15 Nov  San Juan  imbarco 14:00 - partenza 20:00
        Lun 16 Nov  Charlotte Amalie  07:00 - 16:00
        """)
        #expect(!draft.calls.contains { $0.issues.contains(.implausibleLeg) })
    }

    @Test("Una partenza prima dell'arrivo si segnala, senza bloccare")
    func timesOutOfOrder() throws {
        let draft = parser.parse("""
        Nave: Explora III
        Lun 16 Nov  Charlotte Amalie  arrivo 16:00  partenza 07:00
        Mar 17 Nov  Gustavia  08:00 - 18:00
        """)
        let call = try #require(draft.calls.first)
        #expect(call.issues.contains(.timesOutOfOrder))
        #expect(!DraftIssue.timesOutOfOrder.isBlocking)
    }

    @Test("Il riepilogo «7 notti · 7 porti» di Explora torna con quello che si legge")
    func statedCountsMatch() throws {
        let draft = parser.parse(try fixture("explora-caraibi-2026.txt"))
        #expect(draft.statedNights == 7)
        #expect(draft.statedPorts == 7)
        #expect(draft.warnings.isEmpty, "\(draft.warnings)")
    }

    @Test("Se manca un giorno, il riepilogo lo fa notare")
    func missingDayIsNoticed() {
        let draft = parser.parse("""
        Nave: Explora III · 5 notti · 4 porti
        Dom 15 Nov  San Juan  partenza 20:00
        Lun 16 Nov  Charlotte Amalie  07:00 - 16:00
        Mer 18 Nov  Puerto Plata  09:00 - 17:00
        """)
        #expect(draft.warnings.count == 2, "\(draft.warnings)")
    }

    // MARK: Due letture

    @Test("Fra le due letture degli screenshot vince quella che non perde il giorno di mare")
    func betterReadingWins() throws {
        let lines = parser.parse(try fixture("explora-app-screenshot-ocr.txt"))
        let document = parser.parse(try fixture("explora-app-screenshot-documenti.txt"))
        // La lettura per documenti salta «Sab 21 Nov · In mare»: vale meno.
        #expect(!document.calls.contains { $0.isSeaDay })
        #expect(lines.quality > document.quality)
    }

    // MARK: Segnalazione

    @Test("La segnalazione contiene quello che si è letto e il testo originale")
    func reportBody() throws {
        let text = try fixture("explora-caraibi-2026.txt")
        let body = ImportProblemReport.body(draft: parser.parse(text), sourceText: text,
                                            appVersion: "1.0", systemVersion: "26.0")
        #expect(body.contains("Road Bay"))
        #expect(body.contains("Nuovi orizzonti ad Anguilla"))
        #expect(body.hasSuffix("Cruisy 1.0 · iOS 26.0"))
    }
}

/// Le tre letture che l'OCR di iOS fa dei tre screenshot di Explora (simulatore iOS 27,
/// 23 settembre 2026). Ognuna perde qualcosa; unite no.
@Suite("Letture unite")
struct CombinedReadingsTests {
    private let parser = ItineraryTextParser()

    private func drafts() throws -> [ItineraryDraft] {
        try ["explora-app-ios-righe.txt", "explora-app-ios-testo-piccolo.txt", "explora-app-ios-documenti.txt"].map {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\($0)")
            return parser.parse(try String(contentsOf: url, encoding: .utf8))
        }
    }

    @Test("Da sola, nessuna lettura dà una crociera che si può confermare")
    func eachReadingMissesSomething() throws {
        for draft in try drafts() {
            let complete = !draft.hasBlockingIssues && draft.calls.count == 8
                && draft.calls.contains(where: \.isSeaDay)
                && draft.portCalls.allSatisfy { $0.departure != nil || $0.port?.name == "Miami" }
            #expect(!complete, "questa lettura basta da sola: il caso di prova non prova più niente")
        }
    }

    @Test("Unite danno le otto tappe, porti e orari compresi")
    func unionIsComplete() throws {
        let combined = parser.combine(try drafts())
        #expect(!combined.hasBlockingIssues, "\(combined.calls.filter(\.isBlocked).map(\.rawName))")
        let expected: [(Int, String?)] = [(15, "San Juan"), (16, "Road Bay"), (17, "Saint John's"),
                                          (18, "Frederiksted"), (19, "Catalina Island"),
                                          (20, "Puerto Plata"), (21, nil), (22, "Miami")]
        #expect(combined.calls.count == expected.count, "\(combined.calls.map(\.displayName))")
        for (call, (day, port)) in zip(combined.calls, expected) {
            #expect(call.day == day)
            if let port { #expect(call.port?.name == port, "il \(day)") } else { #expect(call.isSeaDay, "il \(day)") }
        }
        let puertoPlata = try #require(combined.calls.first { $0.day == 20 })
        #expect(puertoPlata.arrival == TimeOfDay(hour: 9, minute: 0))
        #expect(puertoPlata.departure == TimeOfDay(hour: 17, minute: 0))
    }

    @Test("L'unione vale più di ogni lettura da sola")
    func unionWins() throws {
        let drafts = try drafts()
        let combined = parser.combine(drafts)
        #expect(drafts.allSatisfy { combined.quality >= $0.quality })
    }
}
