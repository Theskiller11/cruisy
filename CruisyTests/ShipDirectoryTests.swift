import Testing
import Foundation
@testable import Cruisy

/// L'elenco delle navi, che è ciò che fa la magia del "scrivi il nome e si compila".
@Suite("Elenco delle navi")
struct ShipDirectoryTests {

    @Test("L'elenco si carica dal bundle")
    func loads() {
        // Se fallisce, la compilazione automatica smette di funzionare in silenzio.
        #expect(ShipDirectory.shared.count > 800)
    }

    @Test("Trova le navi vere coi dati giusti")
    func knownShips() throws {
        let explora = try #require(ShipDirectory.shared.lookup("Explora I"))
        #expect(explora.imo == "9869875")
        #expect(explora.year == 2023)
        #expect(explora.operatorName.localizedCaseInsensitiveContains("Explora"))
        // Stazza e lunghezza sono fatti verificabili, non approssimazioni.
        #expect(abs(explora.tonnage - 63_621) < 100)
        #expect(abs(explora.length - 248) < 2)
    }

    @Test("Il nome si può scrivere come viene")
    func toleratesTyping() {
        // Maiuscole, accenti e apostrofi non devono cambiare il risultato: è la
        // stessa regola già imparata coi porti, dove "St John's" finiva in Canada.
        for written in ["costa toscana", "COSTA TOSCANA", "Costa  Toscana"] {
            #expect(ShipDirectory.shared.lookup(written)?.imo == "9781891",
                    "fallito su \(written)")
        }
    }

    @Test("Un nome inventato non restituisce una nave a caso")
    func unknownShip() {
        #expect(ShipDirectory.shared.lookup("Qwertyuiop Asdfgh") == nil)
        #expect(ShipDirectory.shared.lookup("ab") == nil)
    }

    @Test("I suggerimenti pescano mentre si digita")
    func suggestions() {
        let byPrefix = ShipDirectory.shared.suggestions(for: "costa t")
        #expect(byPrefix.contains { $0.name.localizedCaseInsensitiveContains("Toscana") })

        // E se il prefisso non basta, si allarga: "seaside" deve trovare MSC Seaside.
        let byContent = ShipDirectory.shared.suggestions(for: "seaside")
        #expect(byContent.contains { $0.name.localizedCaseInsensitiveContains("Seaside") })
    }

    @Test("Le foto non viaggiano nell'app, solo il riferimento")
    func imagesAreReferencesOnly() throws {
        let ship = try #require(ShipDirectory.shared.lookup("Costa Toscana"))
        // Il campo contiene il nome di un file su Wikimedia Commons, non un'immagine:
        // le foto sono libere ma obbligano a citare l'autore, quindi si scaricano a
        // richiesta e si mostrano col credito accanto.
        #expect(!ship.imageFile.hasPrefix("http"))
        #expect(ship.imageFile.count < 256)
    }
}

@Suite("Foto delle navi")
struct ShipPhotoTests {

    @Test("Il riferimento alla foto è un titolo, non un URL già codificato")
    func plainTitles() throws {
        let ship = try #require(ShipDirectory.shared.lookup("Explora I"))
        #expect(ship.imageFile.hasSuffix(".jpg"))
        // Se qui comparisse un %20 il servizio lo ricodificherebbe in %2520 e
        // Commons risponderebbe 404.
        #expect(!ship.imageFile.contains("%"))
        #expect(ship.imageFile.contains(" "))
    }

    @Test("Quasi tutte le navi con misure hanno anche una foto da citare")
    func coverage() {
        // Non è un requisito, è una misura: se crollasse vorrebbe dire che la
        // query verso Wikidata ha smesso di riportare P18.
        #expect(ShipDirectory.shared.count > 1300)
    }

    @Test("Le navi il cui nome comincia per Q ci sono")
    func namesStartingWithQ() throws {
        // Il costruttore scartava le etichette non risolte con `startswith('Q')`,
        // e con loro Quantum of the Seas e tutte le Queen di Cunard.
        let quantum = try #require(ShipDirectory.shared.lookup("Quantum of the Seas"))
        #expect(quantum.imo == "9549463")
        #expect(try #require(ShipDirectory.shared.lookup("Queen Mary 2")).year == 2004)
    }

    @Test("Le navi recenti col nome nella lingua multilingue ci sono")
    func mulLabels() throws {
        // Wikidata ha spostato i nomi propri sulla lingua `mul`: chiedendo solo
        // it|en queste tornavano senza nome e sparivano dall'elenco.
        let icon = try #require(ShipDirectory.shared.lookup("Icon of the Seas"))
        #expect(icon.imo == "9829930")
        #expect(icon.tonnage > 200_000)
        #expect(ShipDirectory.shared.lookup("Star of the Seas") != nil)
        #expect(ShipDirectory.shared.lookup("MSC World Europa") != nil)
    }

    @Test("Il prefisso di registro non è obbligatorio")
    func registryPrefix() throws {
        // Su Wikidata si chiama "MS Brilliance of the Seas"; chi la cerca scrive
        // "Brilliance of the Seas".
        let ship = try #require(ShipDirectory.shared.lookup("Brilliance of the Seas"))
        #expect(ship.imo == "9195200")
    }
}
