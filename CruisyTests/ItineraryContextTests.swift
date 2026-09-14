import Testing
import Foundation
@testable import Cruisy

/// I casi che facevano confusione: contesto fra una tappa e l'altra, e date lette male.
///
/// Nascono da un collaudo vero sul telefono. Sono la ragione per cui il lettore è
/// stato riscritto **a blocchi** invece che riga per riga, ed esistono per impedire
/// che quei casi tornino.
@Suite("Contesto e date")
struct ItineraryContextTests {

    private let parser = ItineraryTextParser()

    // MARK: Contesto fra le tappe

    @Test("Data, porto e orari su righe diverse restano la stessa tappa")
    func multiLineEntry() throws {
        // È la forma più comune nelle email delle compagnie, e con la lettura riga
        // per riga era proprio quella che si rompeva: la data non trovava un porto e
        // il porto non trovava una data.
        let draft = parser.parse("""
        Explora III
        Sabato 15 novembre
        San Juan, Porto Rico
        Imbarco 14:00 · Partenza 20:00
        Domenica 16 novembre
        Charlotte Amalie
        07:00 - 16:00
        """)
        #expect(draft.portCalls.count == 2)
        let sanJuan = try #require(draft.portCalls.first)
        #expect(sanJuan.port?.name.contains("San Juan") == true)
        #expect(sanJuan.arrival == TimeOfDay(hour: 14, minute: 0))
        #expect(sanJuan.departure == TimeOfDay(hour: 20, minute: 0))
    }

    @Test("La prosa fra due tappe non rompe niente e non diventa una tappa")
    func proseBetweenStopsIsAbsorbed() throws {
        let draft = parser.parse("""
        Explora III
        15 nov  San Juan  14:00 - 20:00
        La tua cabina 11024 si trova sul ponte 11, a poppa.
        Il servizio in camera è disponibile ventiquattr'ore su ventiquattro.
        16 nov  Charlotte Amalie  07:00 - 16:00
        """)
        // Due tappe, non quattro.
        #expect(draft.portCalls.count == 2)
        // E il contesto non ha rubato il nome del porto: vince la riga che contiene
        // davvero un porto dell'elenco.
        #expect(draft.portCalls[0].port?.name.contains("San Juan") == true)
        #expect(draft.portCalls[1].port?.name.contains("Charlotte") == true)
    }

    @Test("Una data dentro un testo che non è un itinerario viene scartata")
    func proseWithADateIsDropped() {
        // "Prenotazione del 12/03/2026" ha una data ma nessun porto e nessun orario:
        // segnalarla come riga da sistemare sarebbe un avviso falso, e gli avvisi
        // falsi tolgono peso a quelli veri.
        let draft = parser.parse("""
        Explora III
        Prenotazione n. 4471829 effettuata il 12/03/2026
        15 nov  San Juan  14:00 - 20:00
        16 nov  Charlotte Amalie  07:00 - 16:00
        """)
        #expect(draft.portCalls.count == 2)
        #expect(!draft.hasBlockingIssues)
    }

    @Test("Un blocco non si mangia mezzo documento")
    func blocksHaveALimit() {
        let filler = (1...20).map { "Riga di contorno numero \($0)." }.joined(separator: "\n")
        let draft = parser.parse("""
        Explora III
        15 nov  San Juan  14:00 - 20:00
        \(filler)
        16 nov  Charlotte Amalie  07:00 - 16:00
        """)
        #expect(draft.portCalls.count == 2)
        #expect(draft.portCalls[0].port?.name.contains("San Juan") == true)
    }

    // MARK: Date

    @Test("Un giorno della settimana non viene scambiato per un mese")
    func weekdayIsNotAMonth() throws {
        // "Mar" è martedì **e** marzo. Prima "Mar 17 nov" diventava il 17 marzo, e
        // con esso saltava tutta la crociera.
        let draft = parser.parse("""
        Explora III
        Mar 17 nov  San Juan  14:00 - 20:00
        Mer 18 nov  Charlotte Amalie  07:00 - 16:00
        """)
        let first = try #require(draft.portCalls.first)
        #expect(first.day == 17)
        #expect(first.month == 11, "letto mese \(first.month.map(String.init) ?? "nessuno") invece di novembre")
    }

    @Test("Il giorno da solo, dopo un giorno della settimana, eredita il mese")
    func bareDayInheritsTheMonth() throws {
        // Le tabelle degli itinerari scrivono il mese una volta sola.
        let draft = parser.parse("""
        Explora III
        Sab 15 nov   San Juan        14:00 - 20:00
        Dom 16       Charlotte Amalie 07:00 - 16:00
        Lun 17       Gustavia         08:00 - 18:00
        """)
        #expect(draft.portCalls.count == 3)
        #expect(draft.portCalls.allSatisfy { $0.month == 11 })
        #expect(draft.portCalls.map(\.day) == [15, 16, 17])
    }

    @Test("Se il giorno torna indietro, è cambiato il mese")
    func bareDayRollsOverTheMonth() throws {
        let draft = parser.parse("""
        Costa Toscana
        Lun 30 nov   Savona     17:00 - 19:00
        Mar 1        Marseille  09:00 - 18:00
        """)
        #expect(draft.portCalls.count == 2)
        #expect(draft.portCalls[0].month == 11)
        #expect(draft.portCalls[1].month == 12, "dal 30 all'1 il mese deve avanzare")
    }

    @Test("Le date numeriche seguono l'ordine del documento, non un'ipotesi")
    func numericOrderIsInferredPerDocument() {
        // Una prova interna decide per tutto il testo: se altrove c'è "15/11", allora
        // il primo numero è il giorno anche in "05/11", che da solo sarebbe ambiguo.
        #expect(ItineraryTextParser.inferNumericOrder(in: "05/11 e 15/11") == .dayFirst)
        #expect(ItineraryTextParser.inferNumericOrder(in: "11/05 e 11/15") == .monthFirst)
    }

    @Test("Un documento inglese legge mese/giorno, uno italiano giorno/mese")
    func languageDecidesWhenAmbiguous() throws {
        let english = parser.parse("""
        Norwegian Escape
        11/05  Miami  Embark 1:00 PM  Depart 5:00 PM
        11/06  Nassau  8:00 AM - 5:00 PM
        """)
        let firstEnglish = try #require(english.portCalls.first)
        #expect(firstEnglish.month == 11 && firstEnglish.day == 5)

        let italian = parser.parse("""
        Explora III
        05/11  San Juan  imbarco 14:00 - partenza 20:00
        06/11  Charlotte Amalie  07:00 - 16:00
        """)
        let firstItalian = try #require(italian.portCalls.first)
        #expect(firstItalian.month == 11 && firstItalian.day == 5)
    }

    @Test("Legge le date in formato ISO")
    func isoDates() throws {
        let draft = parser.parse("""
        Explora III
        2026-11-15  San Juan  14:00 - 20:00
        2026-11-16  Charlotte Amalie  07:00 - 16:00
        """)
        let first = try #require(draft.portCalls.first)
        #expect(first.year == 2026 && first.month == 11 && first.day == 15)
    }

    @Test("Legge gli ordinali inglesi e italiani")
    func ordinals() throws {
        let draft = parser.parse("""
        Norwegian Escape
        15th November  Miami  Embark 1:00 PM  Depart 5:00 PM
        November 16th  Nassau  8:00 AM - 5:00 PM
        """)
        #expect(draft.portCalls.count == 2)
        #expect(draft.portCalls.map(\.day) == [15, 16])
        #expect(draft.portCalls.allSatisfy { $0.month == 11 })
    }

    @Test("Un numero di cabina non diventa una data")
    func cabinNumbersAreNotDates() {
        let draft = parser.parse("""
        Explora III
        Cabina 11024 ponte 11
        Suite 8420
        15 nov  San Juan  14:00 - 20:00
        16 nov  Charlotte Amalie  07:00 - 16:00
        """)
        #expect(draft.portCalls.count == 2)
    }

    @Test("Un numero di ponte non diventa un orario")
    func deckNumbersAreNotTimes() throws {
        let draft = parser.parse("""
        Explora III
        15 nov  San Juan  ponte 11  14:00 - 20:00
        """)
        let call = try #require(draft.portCalls.first)
        #expect(call.arrival == TimeOfDay(hour: 14, minute: 0))
        #expect(call.departure == TimeOfDay(hour: 20, minute: 0))
    }

    @Test("Un itinerario a blocchi con tutto sparso resta leggibile")
    func realisticMessyDocument() throws {
        // La forma in cui arrivano davvero: intestazioni, prosa, righe spezzate.
        let draft = parser.parse("""
        La tua crociera è confermata
        Nave: Explora III
        Prenotazione 4471829

        Giorno 1 — Sabato 15 novembre
        San Juan, Porto Rico
        Imbarco dalle 14:00. La nave parte alle 20:00.
        Tutti a bordo entro le 19:00.

        Giorno 2 — Domenica 16 novembre
        Charlotte Amalie, St. Thomas
        Arrivo 07:00 · Partenza 16:00

        Giorno 3 — Lunedì 17 novembre
        Giorno di mare

        Giorno 4 — Martedì 18 novembre
        Puerto Plata, Repubblica Dominicana
        Arrivo 09:00 · Partenza 18:00 · All aboard 17:30
        """)
        #expect(draft.shipName == "Explora III")
        #expect(draft.portCalls.count == 3)
        #expect(draft.calls.filter(\.isSeaDay).count == 1)
        #expect(!draft.hasBlockingIssues, "righe bloccate: \(draft.calls.filter(\.isBlocked).map(\.rawName))")

        let sanJuan = try #require(draft.portCalls.first)
        #expect(sanJuan.arrival == TimeOfDay(hour: 14, minute: 0))
        #expect(sanJuan.departure == TimeOfDay(hour: 20, minute: 0))
        #expect(sanJuan.allAboard == TimeOfDay(hour: 19, minute: 0))
        #expect(!sanJuan.issues.contains(.allAboardAssumed), "l'all aboard era scritto")

        let puertoPlata = try #require(draft.portCalls.last)
        #expect(puertoPlata.allAboard == TimeOfDay(hour: 17, minute: 30))
    }
}
