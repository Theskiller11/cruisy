import Testing
import Foundation
@testable import Cruisy

/// Regole di comportamento aggiunte il 14 settembre 2026, ognuna nata da un difetto
/// trovato nel rapporto sullo stato dell'app.
@Suite("Regole di comportamento")
struct BehaviourRulesTests {

    // MARK: Il mare in porto

    @Test("A nave ormeggiata non si parla del moto della nave")
    func noShipMotionAlongside() {
        #expect(SeaState.moltoMosso.note(.alongside) == nil)
        #expect(SeaState.calmo.note(.alongside) == nil)
    }

    @Test("In navigazione la riga del moto resta")
    func shipMotionUnderway() {
        #expect(SeaState.moltoMosso.note(.underway) == SeaState.moltoMosso.comfort)
    }

    @Test("Col tender la riga parla del tender, e avvisa col mare formato")
    func tenderNoteDependsOnTheSea() {
        let calmo = SeaState.pocoMosso.note(.tender)
        let formato = SeaState.moltoMosso.note(.tender)
        #expect(calmo != nil && formato != nil)
        #expect(calmo != formato)
        #expect(formato == SeaState.agitato.note(.tender))
    }

    // MARK: Le foto

    @Test("Su rete gratuita le foto si scaricano sempre")
    func freeNetworksAllowPhotos() {
        #expect(PhotoDownloadPolicy.allows(isMetered: false, allowsMetered: false))
    }

    @Test("Su rete a consumo solo col permesso")
    func meteredNetworksNeedConsent() {
        #expect(PhotoDownloadPolicy.allows(isMetered: true, allowsMetered: false) == false)
        #expect(PhotoDownloadPolicy.allows(isMetered: true, allowsMetered: true))
    }

    @Test("Per un porto si accettano fotografie, non stemmi e cartine")
    func onlyPhotographsForPorts() {
        #expect(PhotoDownloadPolicy.isPhotograph(URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/ab/Puerto_Plata.jpg")!))
        #expect(PhotoDownloadPolicy.isPhotograph(URL(string: "https://upload.wikimedia.org/x/Vista.JPEG")!))
        #expect(PhotoDownloadPolicy.isPhotograph(URL(string: "https://upload.wikimedia.org/x/Stemma.svg")!) == false)
        #expect(PhotoDownloadPolicy.isPhotograph(URL(string: "https://upload.wikimedia.org/x/Locator_map.png")!) == false)
    }

    // MARK: L'ora di bordo

    @Test("L'orologio che segue i porti non ha uno scarto manuale")
    func automaticClockHasNoManualOffset() {
        #expect(ShipClock(secondsFromGMT: -4 * 3600, source: .portTimeZone).manualOffset == nil)
    }

    @Test("L'orologio impostato a mano dice il suo scarto")
    func manualClockReportsItsOffset() {
        #expect(ShipClock(secondsFromGMT: 3 * 3600, source: .manual).manualOffset == 3 * 3600)
    }

    // MARK: Contrasto

    @Test("Sui pulsanti pieni azzurri il testo scuro si legge, quello bianco no")
    func textOnActionButtons() {
        // Il pulsante «Cercala su Wikidata» era bianco su azzurro: 1,5:1.
        let azzurro = Contrast.RGB(hex: 0x7FD8FF)
        #expect(Contrast.ratio(Contrast.RGB(hex: 0x030C14), azzurro) >= Contrast.bodyMinimum)
        #expect(Contrast.ratio(Contrast.RGB(hex: Palette.inkHex), azzurro) < Contrast.bodyMinimum)
    }

    // MARK: I crediti delle foto

    @Test("Un nome d'autore resta com'è")
    func plainAuthorSurvives() {
        #expect(Commons.cleanAuthor("Martin Le Roy") == "Martin Le Roy")
        #expect(Commons.cleanAuthor("Corey Seeman") == "Corey Seeman")
    }

    @Test("Dalle frasi di Commons esce il nome")
    func sentencesBecomeNames() {
        // Due casi veri, visti sotto le foto dei porti il 14 settembre 2026.
        #expect(Commons.cleanAuthor("Originally uploaded at en.wikipedia by en:User:Evaneggers as e.g. a photo of Gustavia")
                == "Evaneggers")
        #expect(Commons.cleanAuthor("This image or media was taken or created by Matt H. Wade. To see my other works, visit my user page.")
                == "Matt H. Wade")
    }

    @Test("Quello che non si riesce a ridurre a un nome diventa Wikimedia Commons")
    func unreadableAuthorFallsBack() {
        #expect(Commons.cleanAuthor(String(repeating: "descrizione lunghissima senza autore ", count: 3))
                == "Wikimedia Commons")
    }
}
