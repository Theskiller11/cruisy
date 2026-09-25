import Foundation
import Testing
@testable import Cruisy

@Suite("Gli indirizzi con cui si apre l'app")
struct IncomingURLTests {

    @Test("Il tocco su widget e Live Activity porta a Oggi, non a un file")
    func widgetOpensToday() throws {
        // Era il baco: `cruisy://today` veniva letto come una crociera condivisa,
        // e compariva «Non riesco ad aprirlo».
        #expect(IncomingURL(try #require(URL(string: "cruisy://today"))) == .today)
        #expect(IncomingURL(try #require(URL(string: "CRUISY://today"))) == .today)
    }

    @Test("Un file .cruisy è una crociera da leggere")
    func fileIsAVoyage() {
        let file = URL(fileURLWithPath: "/tmp/Crociera.cruisy")
        #expect(IncomingURL(file) == .voyageFile(file))
    }

    @Test("Un indirizzo che non è nostro si ignora")
    func otherLinksAreIgnored() throws {
        #expect(IncomingURL(try #require(URL(string: "https://cruisy.matteopapini.com"))) == .unknown)
    }
}
