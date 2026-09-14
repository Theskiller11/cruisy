import Testing
import Foundation
@testable import Cruisy

@Suite("Lettura dell'itinerario")
struct ItineraryParserTests {

    private let parser = ItineraryTextParser()

    // Un itinerario come lo manda una compagnia italiana.
    private let italian = """
    Explora III
    Sab 15 nov  San Juan, Porto Rico   imbarco 14:00 - partenza 20:00  all aboard 19:00
    Dom 16 nov  Charlotte Amalie, St. Thomas   07:00 - 16:00
    Lun 17 nov  Gustavia   08:00 - 18:00  (tender)
    Mar 18 nov  Giorno di mare
    Mer 19 nov  Puerto Plata   09:00 - 18:00   all aboard 17:30
    Gio 20 nov  Grand Turk   08:00 - 17:00
    Ven 21 nov  Navigazione
    Sab 22 nov  Miami   arrivo 07:00  sbarco
    """

    @Test("Legge una crociera italiana intera")
    func italianItinerary() {
        let draft = parser.parse(italian)
        #expect(draft.shipName == "Explora III")
        #expect(draft.calls.count == 8)
        #expect(draft.portCalls.count == 6)
        #expect(draft.calls.filter(\.isSeaDay).count == 2)
    }

    @Test("Aggancia i porti alle coordinate")
    func portsResolve() {
        let draft = parser.parse(italian)
        let names = draft.portCalls.compactMap { $0.port?.name }
        #expect(names.count == 6, "tutti i porti devono agganciarsi: \(draft.portCalls.map(\.rawName))")
        #expect(draft.portCalls.allSatisfy { !$0.issues.contains(.portUnknown) })
    }

    @Test("L'all aboard non viene scambiato per la partenza")
    func allAboardIsNotDeparture() throws {
        let draft = parser.parse(italian)
        let puertoPlata = try #require(draft.portCalls.first { $0.port?.name.contains("Plata") == true })
        #expect(puertoPlata.arrival == TimeOfDay(hour: 9, minute: 0))
        #expect(puertoPlata.departure == TimeOfDay(hour: 18, minute: 0))
        #expect(puertoPlata.allAboard == TimeOfDay(hour: 17, minute: 30))
        // Era scritto, non dedotto.
        #expect(!puertoPlata.issues.contains(.allAboardAssumed))
    }

    @Test("Dove l'all aboard manca viene proposto e marchiato come tale")
    func assumedAllAboardIsFlagged() throws {
        let draft = parser.parse(italian)
        let grandTurk = try #require(draft.portCalls.first { $0.rawName.lowercased().contains("grand turk") })
        #expect(grandTurk.allAboard == TimeOfDay(hour: 16, minute: 30))   // mezz'ora prima delle 17:00
        #expect(grandTurk.issues.contains(.allAboardAssumed))
    }

    @Test("Col tender il margine proposto è più largo")
    func tenderGetsMoreLead() throws {
        let draft = parser.parse(italian)
        let gustavia = try #require(draft.portCalls.first { $0.rawName.lowercased().contains("gustavia") })
        #expect(gustavia.berth == .tender)
        // Un'ora, non mezza: con la lancia l'ultima corsa parte prima e c'è la coda.
        #expect(gustavia.allAboard == TimeOfDay(hour: 17, minute: 0))
    }

    @Test("Legge un itinerario inglese con AM/PM")
    func englishItinerary() throws {
        let text = """
        Ship: Norwegian Escape
        Sat 15 Nov  Miami, Florida     Embark 1:00 PM   Depart 5:00 PM
        Sun 16 Nov  Day at Sea
        Mon 17 Nov  Ocho Rios, Jamaica  8:00 AM - 5:00 PM  all aboard 4:30 PM
        Tue 18 Nov  George Town         7:00 AM - 3:00 PM  tender
        Wed 19 Nov  Cozumel            10:00 AM - 6:00 PM
        Thu 20 Nov  Miami               7:00 AM
        """
        let draft = parser.parse(text)
        #expect(draft.shipName == "Norwegian Escape")
        #expect(draft.calls.filter(\.isSeaDay).count == 1)

        let ochoRios = try #require(draft.portCalls.first { $0.rawName.lowercased().contains("ocho rios") })
        #expect(ochoRios.arrival == TimeOfDay(hour: 8, minute: 0))
        #expect(ochoRios.departure == TimeOfDay(hour: 17, minute: 0))
        #expect(ochoRios.allAboard == TimeOfDay(hour: 16, minute: 30))
    }

    @Test("Un porto scritto col paese accanto resta un aggancio pulito")
    func portWithCountrySuffixIsNotFlagged() throws {
        // "San Juan, Porto Rico" e "Charlotte Amalie, St. Thomas" sono agganci esatti:
        // la virgola separa il porto da paese o isola. Se venisse tolta prima della
        // ricerca, la corrispondenza ripiegherebbe su un prefisso e queste righe
        // chiederebbero una conferma che non serve — rumore che toglie peso agli
        // avvisi veri.
        let draft = parser.parse(italian)
        for name in ["San Juan", "Charlotte Amalie"] {
            let call = try #require(draft.portCalls.first { $0.port?.name.contains(name) == true })
            #expect(!call.issues.contains(.portUncertain), "\(name) non doveva essere incerto")
            #expect(call.port?.confidence ?? 0 >= 0.9)
        }
    }

    @Test("I nomi commerciali dei porti si agganciano a quelli veri")
    func cruiseAliases() {
        // Sono i casi in cui il dataset grezzo da solo fallisce: la compagnia scrive
        // il nome dell'isola, il database conosce il nome del porto.
        let cases = [("Santorini", "Thira"), ("St. Thomas", "Charlotte Amalie"),
                     ("Roma", "Civitavecchia"), ("St. Maarten", "Philipsburg")]
        for (written, expected) in cases {
            let match = PortGazetteer.shared.lookup(written)
            #expect(match?.name.localizedCaseInsensitiveContains(expected) == true,
                    "\(written) doveva agganciarsi a \(expected), invece: \(match?.name ?? "niente")")
        }
    }

    @Test("Una crociera a cavallo di capodanno non torna indietro di un anno")
    func newYearRollover() {
        let text = """
        Costa Toscana
        28 dic  Savona  17:00 - 19:00
        29 dic  Marseille  09:00 - 18:00
        30 dic  Barcelona  08:00 - 17:00
        31 dic  Giorno di mare
        02 gen  Palermo  09:00 - 18:00
        04 gen  Savona  08:00
        """
        let draft = parser.parse(text)
        let december = draft.calls.filter { $0.month == 12 }.compactMap(\.year)
        let january = draft.calls.filter { $0.month == 1 }.compactMap(\.year)
        #expect(!december.isEmpty && !january.isEmpty)
        // Gennaio dev'essere l'anno **dopo** dicembre, non lo stesso.
        #expect(january.allSatisfy { year in december.allSatisfy { $0 + 1 == year } })
    }

    @Test("Le date senza anno finiscono nel futuro, non nel passato")
    func yearsLandInTheFuture() throws {
        let draft = parser.parse(italian)
        let calendar = Calendar(identifier: .gregorian)
        let first = try #require(draft.calls.first)
        let year = try #require(first.year)
        #expect(year >= calendar.component(.year, from: Date()))
    }

    @Test("Le righe che non sono scali vengono ignorate")
    func noiseIsIgnored() {
        let text = """
        Explora III
        Prenotazione n. 4471829
        Cabina 11024 · ponte 11
        Sab 15 nov  San Juan  14:00 - 20:00
        Grazie per aver scelto la nostra compagnia.
        Dom 16 nov  Charlotte Amalie  07:00 - 16:00
        """
        let draft = parser.parse(text)
        // "Cabina 11024 · ponte 11" non ha una data: non è uno scalo.
        #expect(draft.calls.count == 2)
    }

    @Test("Il bozzetto diventa una crociera vera")
    func draftBecomesVoyage() throws {
        let draft = parser.parse(italian)
        let clock = ShipClock(secondsFromGMT: -4 * 3600)
        let voyage = try #require(draft.voyage(clock: clock))

        #expect(voyage.shipName == "Explora III")
        // I giorni di mare non diventano scali: si ricavano dai buchi.
        #expect(voyage.calls.count == 6)
        #expect(voyage.calls.first?.role == .embarkation)
        #expect(voyage.calls.last?.role == .disembarkation)
        // All'ultimo scalo non c'è né partenza né rientro obbligatorio.
        #expect(voyage.calls.last?.allAboard == nil)
        #expect(voyage.calls.last?.departure == nil)
        // Gli scali sono in ordine di tempo.
        #expect(voyage.calls.map(\.arrival) == voyage.calls.map(\.arrival).sorted())
        // E i giorni di mare ricompaiono da soli.
        #expect(voyage.days(at: voyage.calls[2].arrival).contains { $0.isSeaDay })
    }

    @Test("Un porto sconosciuto blocca la conferma invece di passare in silenzio")
    func unknownPortBlocks() throws {
        let draft = parser.parse("""
        Nave Fantasia
        15 nov  Qwertyuiop Asdfgh   09:00 - 18:00
        16 nov  Miami  08:00
        """)
        let unknown = try #require(draft.calls.first)
        #expect(unknown.issues.contains(.portUnknown))
        #expect(unknown.isBlocked)
        #expect(draft.hasBlockingIssues)
    }

    @Test("Un testo che non è un itinerario non produce una crociera finta")
    func garbageProducesNothing() {
        let draft = parser.parse("Ciao, come stai? Ci vediamo domani per un caffè.")
        #expect(draft.isEmpty)
        #expect(draft.voyage(clock: ShipClock(secondsFromGMT: 0)) == nil)
    }
}
