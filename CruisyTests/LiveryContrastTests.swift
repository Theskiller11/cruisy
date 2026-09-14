import Testing
import Foundation
@testable import Cruisy

/// Ogni livrea passa WCAG AA su ogni coppia inchiostro/fondo che l'app usa, in
/// **entrambe** le modalità.
///
/// Non una livrea a campione: tutte, chiare e scure. Una palette ispirata a una
/// compagnia nasce da colori pensati per uno scafo, non per un'etichetta, e il modo
/// più facile di rompere il contrasto è aggiungere una livrea senza rifare i conti.
/// Qui i conti li fa il test, e se una livrea nuova non regge la build si ferma.
@Suite("Contrasto delle livree")
struct LiveryContrastTests {

    /// Tutte le coppie livrea × modalità.
    static let cases: [(Livery, Livery.Scheme)] = Livery.all.flatMap { livery in
        Livery.Scheme.allCases.map { (livery, $0) }
    }

    private func rgb(_ hex: UInt32) -> Contrast.RGB { Contrast.RGB(hex: hex) }

    @Test("Il catalogo non è vuoto e le livree hanno identità distinte")
    func catalogueIsSane() {
        #expect(Livery.all.count >= 10)
        #expect(Set(Livery.all.map(\.id)).count == Livery.all.count)
        #expect(Livery.all.allSatisfy { !$0.name.isEmpty })
    }

    @Test("Sullo scafo il bianco, il testo di appoggio e il segnale si leggono", arguments: cases)
    func inkOnHull(livery: Livery, scheme: Livery.Scheme) {
        let hull = rgb(livery.hullPair.hex(scheme))
        let deep = rgb(livery.hullDeepPair.hex(scheme))
        let label = "\(livery.id) \(scheme)"
        #expect(Contrast.ratio(rgb(livery.onHullPair.hex(scheme)), hull) >= 7, "\(label): bianco sullo scafo")
        #expect(Contrast.ratio(rgb(livery.onHullPair.hex(scheme)), deep) >= 7, "\(label): bianco sul fondo scuro")
        #expect(Contrast.ratio(rgb(livery.onHullMutedPair.hex(scheme)), hull) >= Contrast.bodyMinimum,
                "\(label): testo di appoggio sullo scafo")
        #expect(Contrast.ratio(rgb(livery.signalOnHullPair.hex(scheme)), hull) >= Contrast.bodyMinimum,
                "\(label): segnale sullo scafo")
    }

    @Test("Sulla carta l'inchiostro e i campi si leggono", arguments: cases)
    func inkOnPaper(livery: Livery, scheme: Livery.Scheme) {
        let paper = rgb(livery.paperPair.hex(scheme))
        let label = "\(livery.id) \(scheme)"
        #expect(Contrast.ratio(rgb(livery.inkPair.hex(scheme)), paper) >= 7, "\(label): inchiostro")
        #expect(Contrast.ratio(rgb(livery.fieldPair.hex(scheme)), paper) >= Contrast.bodyMinimum,
                "\(label): etichette dei campi")
        // Anche sulla carta del biglietto di dietro.
        let shade = rgb(livery.paperShadePair.hex(scheme))
        #expect(Contrast.ratio(rgb(livery.inkPair.hex(scheme)), shade) >= Contrast.bodyMinimum,
                "\(label): inchiostro sul biglietto dietro")
        // E la carta si stacca dallo scafo: un biglietto scuro su uno scafo scuro
        // deve comunque leggersi come un cartoncino appoggiato.
        #expect(Contrast.ratio(paper, rgb(livery.hullPair.hex(scheme))) >= 1.4,
                "\(label): la carta non si stacca dallo scafo")
    }

    @Test("Il segnale regge come grafica e come testo piccolo", arguments: cases)
    func signalOnPaper(livery: Livery, scheme: Livery.Scheme) {
        let paper = rgb(livery.paperPair.hex(scheme))
        let label = "\(livery.id) \(scheme)"
        // Il timbro e l'ora stampata: grafica e testo grande, 3:1.
        #expect(Contrast.ratio(rgb(livery.signalPair.hex(scheme)), paper) >= Contrast.largeTextMinimum,
                "\(label): segnale come timbro")
        // L'etichetta «RIENTRO A BORDO»: testo piccolo, 4,5:1.
        #expect(Contrast.ratio(rgb(livery.signalInkPair.hex(scheme)), paper) >= Contrast.bodyMinimum,
                "\(label): segnale come etichetta")
    }

    @Test("La tinta dei controlli si legge sul fondo di sistema", arguments: Livery.all)
    func tintOnSystemBackground(livery: Livery) {
        #expect(Contrast.ratio(rgb(livery.tintPair.light), rgb(0xFFFFFF)) >= Contrast.bodyMinimum,
                "\(livery.id): tinta in chiaro")
        #expect(Contrast.ratio(rgb(livery.tintPair.dark), rgb(0x000000)) >= Contrast.bodyMinimum,
                "\(livery.id): tinta in scuro")
    }

    @Test("Schiarire fino al contrasto: si ferma appena basta, e non tocca chi già regge")
    func lighteningStopsAtThreshold() {
        let navy: UInt32 = 0x0E2A47
        let lifted = Livery.lightened(navy, toContrast: 4.5, over: 0x000000)
        #expect(Contrast.ratio(rgb(lifted), rgb(0x000000)) >= 4.5)
        // Un passo indietro non basterebbe: la schiaritura è la minima.
        let previous = Livery.mix(navy, 0xFFFFFF, max(0, mixShare(from: navy, to: lifted) - 0.02))
        #expect(Contrast.ratio(rgb(previous), rgb(0x000000)) < 4.5 || previous == navy)
        // Il bianco sul nero regge già: torna com'è.
        #expect(Livery.lightened(0xFFFFFF, toContrast: 4.5, over: 0x000000) == 0xFFFFFF)
    }

    /// Ricava la quota di bianco con cui `lifted` è stato ottenuto da `base`.
    private func mixShare(from base: UInt32, to lifted: UInt32) -> Double {
        let b = Double(base & 0xFF), l = Double(lifted & 0xFF)
        return b >= 255 ? 0 : (l - b) / (255 - b)
    }

    @Test("La livrea si aggancia all'armatore, e senza armatore è quella di Cruisy")
    func operatorMapping() {
        #expect(Livery.forOperator("MSC Crociere").id == "oltremare")
        #expect(Livery.forOperator("Explora Journeys").id == "notte-oro")
        #expect(Livery.forOperator("Virgin Voyages").id == "rosso")
        #expect(Livery.forOperator("Costa Crociere").id == "blu-giallo")
        #expect(Livery.forOperator("Royal Caribbean International").id == "navy-oro")
        #expect(Livery.forOperator("") == .cruisy)
        #expect(Livery.forOperator(nil) == .cruisy)
        #expect(Livery.forOperator("United States Navy") == .cruisy)
        // La scelta dell'utente vince su tutto.
        #expect(Livery.resolve(.cruisy, operatorName: "MSC Crociere") == .cruisy)
        #expect(Livery.resolve(.company, operatorName: "MSC Crociere").id == "oltremare")
    }

    @Test("I nomi delle livree sono nomi di colori, non di compagnie")
    func namesAreNotBrands() {
        let brands = ["msc", "explora", "virgin", "costa", "royal", "celebrity", "carnival",
                      "norwegian", "princess", "holland", "disney", "aida", "cunard", "tui",
                      "viking", "ponant", "hurtigruten"]
        for livery in Livery.all {
            let name = livery.name.lowercased()
            #expect(!brands.contains { name.contains($0) }, "«\(livery.name)» nomina una compagnia")
        }
    }
}

/// Il cielo del giorno di mare: luminoso di giorno, caldo all'alba e al tramonto,
/// scuro di notte, e continuo. Sopra non c'è testo: il contrasto non è affar suo.
@Suite("Il cielo del giorno di mare")
struct SeaSceneContrastTests {

    private func luminance(_ hex: UInt32) -> Double { Contrast.relativeLuminance(Contrast.RGB(hex: hex)) }

    @Test("Di giorno il cielo è chiaro, di notte scuro")
    func dayIsBrightNightIsDark() {
        let noon = SeaSky.at(hour: 13), midnight = SeaSky.at(hour: 1)
        #expect(luminance(noon.horizon) > 0.6, "l'orizzonte di giorno è celeste chiaro")
        #expect(luminance(noon.zenith) > 0.2, "lo zenit di giorno è blu vivo")
        #expect(luminance(midnight.zenith) < 0.02)
        #expect(luminance(noon.horizon) > luminance(midnight.horizon) * 8)
    }

    @Test("All'alba e al tramonto l'orizzonte è caldo")
    func dawnAndDuskAreWarm() {
        for hour in [6.5, 18.5] {
            let horizon = SeaSky.at(hour: hour).horizon
            let red = (horizon >> 16) & 255, blue = horizon & 255
            #expect(red > blue + 80, "alle \(hour) l'orizzonte non è caldo: \(String(horizon, radix: 16))")
        }
    }

    @Test("Il cielo scorre senza scatti fra un quarto d'ora e l'altro")
    func skyIsContinuous() {
        func channels(_ hex: UInt32) -> [Int] { [Int((hex >> 16) & 255), Int((hex >> 8) & 255), Int(hex & 255)] }
        var previous = SeaSky.at(hour: 0)
        for quarter in stride(from: 0.25, through: 24, by: 0.25) {
            let current = SeaSky.at(hour: quarter)
            let step = max(zip(channels(previous.zenith), channels(current.zenith)).map { abs($0 - $1) }.max() ?? 0,
                           zip(channels(previous.horizon), channels(current.horizon)).map { abs($0 - $1) }.max() ?? 0)
            #expect(step <= 40, "scatto di \(step) livelli alle \(quarter)")
            previous = current
        }
    }

    @Test("Il sole sta in cielo di giorno e la luna di notte")
    func sunAndMoonTakeTurns() {
        #expect(SeaSky.sunProgress(hour: 12) != nil)
        #expect(SeaSky.moonProgress(hour: 12) == nil)
        #expect(SeaSky.sunProgress(hour: 2) == nil)
        #expect(SeaSky.moonProgress(hour: 2) != nil)
        // Il sole sorge a sinistra e tramonta a destra.
        #expect(SeaSky.sunProgress(hour: SeaSky.sunrise) == 0)
        #expect(SeaSky.sunProgress(hour: SeaSky.sunset) == 1)
    }
}
