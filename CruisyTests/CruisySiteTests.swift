import Testing
import Foundation
@testable import Cruisy

/// Gli indirizzi del sito che l'app apre dalle Impostazioni.
@Suite("Sito di Cruisy")
struct CruisySiteTests {
    @Test("in italiano si apre la pagina dall'inizio")
    func italianOpensTheTop() {
        #expect(CruisySite.url(.privacy, language: "it").absoluteString == "https://cruisy.matteopapini.com/privacy")
        #expect(CruisySite.url(.support, language: "it-IT").absoluteString == "https://cruisy.matteopapini.com/assistenza")
    }

    @Test("in un'altra lingua si arriva alla parte inglese")
    func otherLanguagesJumpToEnglish() {
        #expect(CruisySite.url(.privacy, language: "en").absoluteString == "https://cruisy.matteopapini.com/privacy#english")
        #expect(CruisySite.url(.support, language: "de").absoluteString == "https://cruisy.matteopapini.com/assistenza#english")
    }
}
