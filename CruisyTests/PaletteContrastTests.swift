import Testing
import Foundation
@testable import Cruisy

/// I livelli di inchiostro della palette, tenuti a norma da un test invece che
/// dall'occhio.
///
/// L'audit del brief aveva trovato etichette a `rgba(234,242,248,.32)`: circa 1,6:1
/// sul fondo, cioè illeggibili. Il problema di quel genere di errore è che si ripresenta
/// da solo, perché "un po' più tenue" sembra sempre più elegante. Qui la soglia è
/// eseguibile: se qualcuno abbassa un'opacità, la build si ferma.
@Suite("Contrasto della palette")
struct PaletteContrastTests {

    private let ink = Contrast.RGB(hex: Palette.inkHex)
    /// Il fondo dell'app.
    private let sea = Contrast.RGB(hex: Palette.seaHex)
    /// Il fondo di una card di vetro: più chiaro del fondo, quindi **peggiore** per un
    /// inchiostro chiaro. È il caso da verificare, non quello facile.
    private let glass = Contrast.RGB(hex: Palette.glassOverSeaHex)

    @Test("Il testo portante è ampiamente sopra la soglia, ovunque stia")
    func primaryInk() {
        #expect(Contrast.ratio(ofInk: ink, atAlpha: Palette.primaryAlpha, over: sea) >= 7)
        #expect(Contrast.ratio(ofInk: ink, atAlpha: Palette.primaryAlpha, over: glass) >= 7)
    }

    @Test("Il testo di appoggio supera 4,5:1 sul fondo e sul vetro")
    func secondaryInk() {
        #expect(Contrast.ratio(ofInk: ink, atAlpha: Palette.secondaryAlpha, over: sea)
                >= Contrast.bodyMinimum)
        #expect(Contrast.ratio(ofInk: ink, atAlpha: Palette.secondaryAlpha, over: glass)
                >= Contrast.bodyMinimum)
    }

    @Test("Anche il livello più tenue resta testo leggibile, non decorazione")
    func tertiaryInk() {
        #expect(Contrast.ratio(ofInk: ink, atAlpha: Palette.tertiaryAlpha, over: sea)
                >= Contrast.bodyMinimum)
        #expect(Contrast.ratio(ofInk: ink, atAlpha: Palette.tertiaryAlpha, over: glass)
                >= Contrast.bodyMinimum)
    }

    @Test("I livelli sono in ordine e nessuno scende sotto il pavimento")
    func levelsAreOrdered() {
        #expect(Palette.primaryAlpha > Palette.secondaryAlpha)
        #expect(Palette.secondaryAlpha > Palette.tertiaryAlpha)
        // Il valore che l'audit ha bocciato. Se qualcuno ci riprova, questo test lo dice.
        #expect(Palette.tertiaryAlpha > 0.45)
    }

    @Test("Gli accenti si leggono sul fondo scuro")
    func accentsAreLegible() {
        let underway = Contrast.RGB(hex: 0x46E0C0)
        let ashore = Contrast.RGB(hex: 0xFFB454)
        let action = Contrast.RGB(hex: 0x7FD8FF)

        for accent in [underway, ashore, action] {
            #expect(Contrast.ratio(accent, sea) >= Contrast.bodyMinimum)
            #expect(Contrast.ratio(accent, glass) >= Contrast.bodyMinimum)
        }
    }

    @Test("La matematica del contrasto è quella dello standard")
    func contrastMathIsCorrect() {
        let white = Contrast.RGB(1, 1, 1), black = Contrast.RGB(0, 0, 0)
        // Bianco su nero è il massimo possibile: 21:1.
        #expect(abs(Contrast.ratio(white, black) - 21) < 0.01)
        #expect(abs(Contrast.ratio(white, white) - 1) < 0.001)
        // Il compositing a piena opacità restituisce il colore stesso.
        #expect(Contrast.composite(white, over: black, alpha: 1) == white)
        #expect(Contrast.composite(white, over: black, alpha: 0) == black)
    }
}

/// Il cielo che segue l'ora non può schiarire più di così.
///
/// Il fondo cambia col passare del giorno, e un fondo più chiaro è il caso
/// **peggiore** per un inchiostro chiaro. Questi test fissano il tetto: se
/// qualcuno accende ancora di più il mezzogiorno, la build si ferma invece di
/// lasciar scoprire l'illeggibilità a bordo, col sole negli occhi.
@Suite("Contrasto col cielo del giorno")
struct SkyContrastTests {

    private let ink = Contrast.RGB(hex: Palette.inkHex)

    /// Il vetro sopra un fondo: la card è più chiara di ciò che ha sotto, quindi
    /// è lei il caso da verificare, non il fondo nudo.
    private func glass(over hex: UInt32) -> Contrast.RGB {
        let lift = 0.055
        func channel(_ shift: UInt32) -> UInt32 {
            let base = Double((hex >> shift) & 255)
            return UInt32((base + (255 - base) * lift).rounded())
        }
        return Contrast.RGB(hex: (channel(16) << 16) | (channel(8) << 8) | channel(0))
    }

    /// I tre canali di un colore, come numeri interi.
    private func channels(_ hex: UInt32) -> [Int] {
        [Int((hex >> 16) & 255), Int((hex >> 8) & 255), Int(hex & 255)]
    }

    /// Di quanto si allontanano due colori, sommando i tre canali.
    private func distance(_ a: UInt32, _ b: UInt32) -> Int {
        zip(channels(a), channels(b)).reduce(0) { $0 + abs($1.0 - $1.1) }
    }

    /// Il salto massimo su un singolo canale fra due cieli.
    private func maximumStep(_ a: Palette.Sky, _ b: Palette.Sky) -> Int {
        var worst = 0
        for (first, second) in zip(a.stops, b.stops) {
            for (x, y) in zip(channels(first), channels(second)) {
                worst = max(worst, abs(x - y))
            }
        }
        return worst
    }

    /// Il cielo a ogni quarto d'ora del giro completo.
    private func everySky(inPort: Bool) -> [(hour: Double, sky: Palette.Sky)] {
        stride(from: 0.0, to: 24.0, by: 0.25).map { ($0, Palette.sky(hour: $0, inPort: inPort)) }
    }

    @Test("Ogni fermata di ogni ora regge l'inchiostro più tenue")
    func tertiaryInkOnEveryStop() {
        // Non basta controllare la cima del gradiente: le card **scorrono** sopra
        // uno sfondo fermo, quindi un'etichetta terziaria può finire sopra
        // qualunque punto di esso.
        for inPort in [false, true] {
            for (hour, sky) in everySky(inPort: inPort) {
                for stop in sky.stops {
                    let nudo = Contrast.RGB(hex: stop)
                    #expect(Contrast.ratio(ofInk: ink, atAlpha: Palette.tertiaryAlpha, over: nudo)
                            >= Contrast.bodyMinimum,
                            "fondo nudo alle \(hour), fermata \(String(stop, radix: 16))")
                    #expect(Contrast.ratio(ofInk: ink, atAlpha: Palette.tertiaryAlpha,
                                           over: glass(over: stop)) >= Contrast.bodyMinimum,
                            "sotto vetro alle \(hour), fermata \(String(stop, radix: 16))")
                }
            }
        }
    }

    @Test("Gli accenti si leggono su qualunque fermata")
    func accentsOnEveryStop() {
        for inPort in [false, true] {
            for stop in Palette.allSkyStops(inPort: inPort) {
                let fondo = Contrast.RGB(hex: stop)
                for accent in [Contrast.RGB(hex: 0x46E0C0), Contrast.RGB(hex: 0xFFB454),
                               Contrast.RGB(hex: 0x7FD8FF)] {
                    #expect(Contrast.ratio(accent, fondo) >= Contrast.bodyMinimum)
                }
            }
        }
    }

    @Test("Il gradiente scende: più chiaro in cima, come una carta illuminata da sopra")
    func gradientDescends() {
        for inPort in [false, true] {
            for (hour, sky) in everySky(inPort: inPort) {
                let l = sky.stops.map { Contrast.relativeLuminance(Contrast.RGB(hex: $0)) }
                #expect(l[0] >= l[1], "cima più scura del centro alle \(hour)")
                #expect(l[1] >= l[2], "centro più scuro del fondo alle \(hour)")
            }
        }
    }

    @Test("Il ciclo è continuo: nessuno scalino fra un'ora e la successiva")
    func skyIsContinuous() {
        for inPort in [false, true] {
            var precedente = Palette.sky(hour: 0, inPort: inPort)
            for quarter in stride(from: 0.25, through: 24, by: 0.25) {
                let corrente = Palette.sky(hour: quarter, inPort: inPort)
                let salto = maximumStep(precedente, corrente)
                // Un quarto d'ora non può cambiare un canale di più di sei livelli:
                // se no il cielo scatta invece di scorrere.
                #expect(salto <= 6)
                precedente = corrente
            }
        }
    }

    @Test("Mezzanotte e mezzogiorno non si somigliano")
    func nightIsNotNoon() {
        // Con la luminosità bloccata dal contrasto, l'unica cosa che distingue le ore
        // è la **tinta**: se giorno e notte finissero vicini, il ciclo sparirebbe.
        // Perciò non basta che siano diversi, devono esserlo di parecchio.
        for inPort in [false, true] {
            let notte = Palette.sky(hour: 0, inPort: inPort).top
            let giorno = Palette.sky(hour: 12, inPort: inPort).top
            let distanza = distance(notte, giorno)
            #expect(distanza >= 24, "notte e giorno troppo simili: \(distanza) livelli")
        }
    }

    @Test("Il giorno è comunque più luminoso della notte")
    func noonOutshinesMidnight() {
        // Il tetto di contrasto impedisce un vero abbagliamento, ma un po' di
        // dislivello deve restare: è quello che Matteo ha chiesto vedendo i fondi.
        for inPort in [false, true] {
            let notte = Contrast.relativeLuminance(
                Contrast.RGB(hex: Palette.sky(hour: 0, inPort: inPort).top))
            let giorno = Contrast.relativeLuminance(
                Contrast.RGB(hex: Palette.sky(hour: 12, inPort: inPort).top))
            #expect(giorno > notte * 1.2)
        }
    }
}
