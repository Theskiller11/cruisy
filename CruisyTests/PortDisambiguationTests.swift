import Testing
import Foundation
@testable import Cruisy

/// I nomi di porto ambigui.
///
/// Nato da un caso vero trovato sul telefono: una crociera ai Caraibi con scalo a
/// **St John's (Antigua)** finiva col segnaposto a **St John's (Terranova)**, tremila
/// miglia più a nord, e senza il minimo avviso perché il nome corrispondeva in pieno.
@Suite("Porti omonimi")
struct PortDisambiguationTests {

    private let parser = ItineraryTextParser()

    @Test("Un apostrofo non deve cambiare il porto")
    func apostropheFoldsAway() {
        // Era il baco all'origine: l'apostrofo diventava uno spazio, quindi
        // "St John's" e "St Johns" erano due chiavi diverse — e nei dati esistono
        // entrambe, per due porti a tremila miglia di distanza.
        #expect(PortGazetteer.fold("St John's") == PortGazetteer.fold("St Johns"))
        #expect(PortGazetteer.fold("St John\u{2019}s") == "st johns")
    }

    @Test("Il nome ambiguo restituisce tutti i candidati, non il primo che capita")
    func ambiguityIsVisible() {
        let candidates = PortGazetteer.shared.candidates("St John's")
        #expect(candidates.count >= 2, "St John's esiste ad Antigua e a Terranova")
        #expect(candidates.contains { $0.coordinate.latitude < 20 })   // Antigua
        #expect(candidates.contains { $0.coordinate.latitude > 40 })   // Terranova
    }

    @Test("Il paese scritto accanto decide da solo")
    func countryHintWins() throws {
        var calls = [DraftCall(rawName: "St John's, Antigua",
                               portCandidates: PortGazetteer.shared.candidates("St John's"),
                               sourceLine: "3 nov  St John's, Antigua  09:00 - 19:00")]
        PortDisambiguator.resolve(&calls)
        let port = try #require(calls[0].port)
        #expect(port.country.localizedCaseInsensitiveContains("Antigua"))
        #expect(port.coordinate.latitude < 20)
        #expect(!calls[0].issues.contains(.portUncertain))
    }

    @Test("Senza il paese, decidono gli altri scali della crociera")
    func geographyWins() throws {
        // Il documento non dice dove sia St John's, ma la crociera sì: gli scali
        // certi stanno tutti ai Caraibi.
        let text = """
        Explora III
        1 nov  San Juan  17:00 - 20:00
        3 nov  St John's  09:00 - 19:00
        5 nov  Puerto Plata  09:00 - 18:00
        7 nov  Miami  07:00
        """
        let draft = parser.parse(text)
        let stJohns = try #require(draft.portCalls.first { $0.rawName.localizedCaseInsensitiveContains("john") })
        let port = try #require(stJohns.port)
        // Antigua, non Terranova.
        #expect(port.coordinate.latitude < 25,
                "scelto \(port.name), \(port.country) a \(port.coordinate.latitude)°")
        #expect(Geo.nauticalMiles(from: port.coordinate,
                                 to: Coordinate(latitude: 17.12, longitude: -61.85)) < 60)
    }

    @Test("Una crociera nordatlantica sceglie l'altro St John's")
    func geographyWorksBothWays() throws {
        // La prova che non si sta solo preferendo i Caraibi: con gli stessi dati e
        // un itinerario nordico, deve vincere Terranova.
        let text = """
        Nave Boreale
        1 lug  Reykjavik  17:00 - 20:00
        4 lug  St John's  09:00 - 19:00
        6 lug  Halifax  08:00 - 17:00
        """
        let draft = parser.parse(text)
        let stJohns = try #require(draft.portCalls.first { $0.rawName.localizedCaseInsensitiveContains("john") })
        let port = try #require(stJohns.port)
        #expect(port.coordinate.latitude > 40,
                "scelto \(port.name), \(port.country) a \(port.coordinate.latitude)°")
    }

    @Test("Nessuno scalo finisce a migliaia di miglia dai suoi vicini")
    func noCallIsImplausiblyFar() throws {
        let text = """
        Explora III
        1 nov  San Juan  17:00 - 20:00
        3 nov  St John's  09:00 - 19:00
        4 nov  Frederiksted  08:00 - 17:00
        5 nov  Puerto Plata  09:00 - 18:00
        7 nov  Miami  07:00
        """
        let draft = parser.parse(text)
        let coordinates = draft.portCalls.compactMap { $0.port?.coordinate }
        #expect(coordinates.count == 5)
        // Una crociera di una settimana non fa salti da duemila miglia fra due scali.
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let miles = Geo.nauticalMiles(from: a, to: b)
            #expect(miles < 2_000, "salto di \(Int(miles)) mn fra due scali consecutivi")
        }
    }

    @Test("Il paese arriva per intero, non troncato a due lettere")
    func countryIsNotTruncated() throws {
        // Mostrava "An" e "Un" perché il campo veniva tagliato a due caratteri di un
        // nome intero.
        let miami = try #require(PortGazetteer.shared.candidates("Miami").first)
        #expect(miami.country.count > 2)
        #expect(miami.country.localizedCaseInsensitiveContains("United States"))
    }
}
