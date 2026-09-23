import Testing
import Foundation
@testable import Cruisy

/// Due documenti veri, mandati da Matteo il 23 settembre 2026: il PDF dell'itinerario
/// che Explora manda per email e tre screenshot della sua app, letti con l'OCR.
///
/// Con il PDF non si ricavava niente: il porto sta nel titolo **sopra** la data
/// («Giorno 2: Nuovi orizzonti ad Anguilla»), il primo giorno ha solo «Partenza
/// 17:00» e veniva preso per l'arrivo, il giorno di mare non ha data, e prosa e piè di
/// pagina finivano dentro le tappe. Negli screenshot gli orari della cena sembravano
/// orari della nave, e le tappe si ripetevano da una foto all'altra.
@Suite("Itinerari Explora veri")
struct ExploraImportTests {

    private func draft(_ file: String) throws -> ItineraryDraft {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/\(file)")
        return ItineraryTextParser().parse(try String(contentsOf: url, encoding: .utf8))
    }

    /// Le otto tappe della crociera, uguali in tutti e due i documenti.
    private let expected: [(day: Int, port: String?)] = [
        (15, "San Juan"), (16, "Road Bay"), (17, "Saint John's"), (18, "Frederiksted"),
        (19, "Catalina Island"), (20, "Puerto Plata"), (21, nil), (22, "Miami"),
    ]

    @Test("Il PDF e gli screenshot danno le stesse otto tappe",
          arguments: ["explora-caraibi-2026.txt", "explora-app-screenshot-ocr.txt"])
    func eightCalls(_ file: String) throws {
        let draft = try draft(file)
        #expect(draft.calls.count == 8, "\(draft.calls.map(\.rawName))")
        for (call, stop) in zip(draft.calls, expected) {
            #expect(call.day == stop.day && call.month == 11 && call.year == 2026)
            if let port = stop.port {
                #expect(call.port?.name == port, "giorno \(stop.day): \(call.rawName)")
            } else {
                #expect(call.isSeaDay, "il 21 è in mare")
            }
        }
        #expect(!draft.hasBlockingIssues, "\(draft.calls.filter(\.isBlocked).map(\.rawName))")
    }

    @Test("Gli orari vanno dove dice l'etichetta",
          arguments: ["explora-caraibi-2026.txt", "explora-app-screenshot-ocr.txt"])
    func labelledTimes(_ file: String) throws {
        let calls = try draft(file).calls
        // Il primo giorno c'è solo la partenza: non deve diventare l'arrivo.
        #expect(calls[0].arrival == nil)
        #expect(calls[0].departure == TimeOfDay(hour: 17, minute: 0))
        #expect(calls[0].issues.contains(.missingTimes), "l'orario d'imbarco manca, e va detto")
        #expect(calls[3].arrival == TimeOfDay(hour: 8, minute: 0))
        #expect(calls[3].departure == TimeOfDay(hour: 16, minute: 0))
        #expect(calls[7].arrival == TimeOfDay(hour: 8, minute: 0))
    }

    @Test("Negli screenshot gli orari della cena non sono orari della nave")
    func restaurantHoursAreIgnored() throws {
        let calls = try draft("explora-app-screenshot-ocr.txt").calls
        // «Fil Rouge · Deck 4 · 20:00 - 22:00» sta sotto San Juan.
        #expect(calls[0].departure == TimeOfDay(hour: 17, minute: 0))
        #expect(calls[2].departure == TimeOfDay(hour: 19, minute: 0))
    }

    @Test("La nave si trova anche a pagina quattro")
    func shipName() throws {
        #expect(try draft("explora-caraibi-2026.txt").shipName == "Explora III")
    }

    @Test("Il tender scritto nel titolo del giorno resta tender")
    func tenderFromText() throws {
        let calls = try draft("explora-caraibi-2026.txt").calls
        #expect(calls[1].berth == .tender)
        #expect(calls[4].berth == .tender)
        #expect(calls[5].berth == .dock)
    }
}

/// Ogni isola che sta al posto di un porto deve portare a un porto che esiste.
@Suite("Isole e porti")
struct ItineraryAliasTests {
    @Test("Ogni alias esiste nell'elenco dei porti")
    func aliasesResolve() {
        for (island, port) in ItineraryTextParser.portAliases {
            #expect(!PortGazetteer.shared.exactCandidates(port).isEmpty, "\(island) → \(port)")
        }
    }
}
