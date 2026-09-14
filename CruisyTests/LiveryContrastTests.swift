import Testing
import Foundation
@testable import Cruisy

/// Ogni livrea passa WCAG AA su ogni coppia inchiostro/fondo che l'app usa.
///
/// Non una livrea a campione: **tutte**. Una palette ispirata a una compagnia nasce
/// da colori pensati per uno scafo, non per un'etichetta, e il modo più facile di
/// rompere il contrasto è aggiungere una livrea senza rifare i conti. Qui i conti
/// li fa il test, e se una livrea nuova non regge la build si ferma.
@Suite("Contrasto delle livree")
struct LiveryContrastTests {

    private let paper = Contrast.RGB(hex: Livery.paperHex)
    private let onHull = Contrast.RGB(hex: Livery.onHullHex)

    @Test("Il catalogo non è vuoto e le livree hanno identità distinte")
    func catalogueIsSane() {
        #expect(Livery.all.count >= 10)
        #expect(Set(Livery.all.map(\.id)).count == Livery.all.count)
        #expect(Livery.all.allSatisfy { !$0.name.isEmpty })
    }

    @Test("Sullo scafo il bianco e il testo di appoggio si leggono", arguments: Livery.all)
    func inkOnHull(livery: Livery) {
        let hull = Contrast.RGB(hex: livery.hullHex)
        let deep = Contrast.RGB(hex: livery.hullDeepHex)
        #expect(Contrast.ratio(onHull, hull) >= 7, "\(livery.id): bianco sullo scafo")
        #expect(Contrast.ratio(onHull, deep) >= 7, "\(livery.id): bianco sul fondo scuro")
        #expect(Contrast.ratio(Contrast.RGB(hex: livery.onHullMutedHex), hull) >= Contrast.bodyMinimum,
                "\(livery.id): testo di appoggio sullo scafo")
        #expect(Contrast.ratio(Contrast.RGB(hex: livery.signalOnHullHex), hull) >= Contrast.bodyMinimum,
                "\(livery.id): segnale sullo scafo")
    }

    @Test("Sulla carta l'inchiostro e i campi si leggono", arguments: Livery.all)
    func inkOnPaper(livery: Livery) {
        #expect(Contrast.ratio(Contrast.RGB(hex: livery.inkHex), paper) >= 7, "\(livery.id): inchiostro")
        #expect(Contrast.ratio(Contrast.RGB(hex: livery.fieldHex), paper) >= Contrast.bodyMinimum,
                "\(livery.id): etichette dei campi")
        // Anche sulla carta del biglietto di dietro, che è più scura.
        let shade = Contrast.RGB(hex: livery.paperShadeHex)
        #expect(Contrast.ratio(Contrast.RGB(hex: livery.inkHex), shade) >= Contrast.bodyMinimum,
                "\(livery.id): inchiostro sul biglietto dietro")
    }

    @Test("Il segnale regge come grafica e come testo piccolo", arguments: Livery.all)
    func signalOnPaper(livery: Livery) {
        // Il timbro e l'ora stampata: grafica e testo grande, 3:1.
        #expect(Contrast.ratio(Contrast.RGB(hex: livery.signalHex), paper) >= Contrast.largeTextMinimum,
                "\(livery.id): segnale come timbro")
        // L'etichetta «RIENTRO A BORDO»: testo piccolo, 4,5:1.
        #expect(Contrast.ratio(Contrast.RGB(hex: livery.signalInkHex), paper) >= Contrast.bodyMinimum,
                "\(livery.id): segnale come etichetta")
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

/// Il cielo del giorno di mare non può schiarire dove poggia il testo.
@Suite("Contrasto del cielo")
struct SeaSceneContrastTests {

    @Test("Lo zenit regge il bianco a ogni ora del giorno")
    func zenithStaysDark() {
        let white = Contrast.RGB(1, 1, 1)
        for quarter in stride(from: 0.0, to: 24.0, by: 0.25) {
            let sky = SeaSky.at(hour: quarter)
            #expect(Contrast.ratio(white, Contrast.RGB(hex: sky.zenith)) >= Contrast.bodyMinimum,
                    "zenit alle \(quarter): \(String(sky.zenith, radix: 16))")
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
