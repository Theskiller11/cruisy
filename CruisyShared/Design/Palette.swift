import SwiftUI

/// I colori di Cruisy, con i livelli di inchiostro scelti per superare WCAG AA
/// e non per assomigliare al mockup.
///
/// Il brief usava opacità 0.32–0.45 per le etichette: da 1.6:1 a 2.9:1 sul fondo
/// dell'app, e peggio ancora sopra le card di vetro (che sono *più chiare* del fondo,
/// quindi abbassano ancora il contrasto di un inchiostro chiaro). I tre livelli qui
/// sotto sono verificati da `PaletteContrastTests`, sia sul fondo sia sulla card.
public enum Palette {

    // MARK: Inchiostro

    /// Bianco leggermente virato al ghiaccio: il colore del testo su tutta l'app.
    public static let inkHex: UInt32 = 0xEAF2F8
    public static let ink = Color(hex: inkHex)

    /// Opacità dell'inchiostro. Non scendere sotto `tertiaryAlpha`: sotto si va
    /// fuori norma, ed è la cosa che l'audit ha bocciato nel brief.
    public static let primaryAlpha = 1.00
    public static let secondaryAlpha = 0.68
    public static let tertiaryAlpha = 0.52

    /// Testo portante: valori, titoli, il countdown.
    public static let inkPrimary = ink
    /// Testo di appoggio: sottotitoli, descrizioni.
    public static let inkSecondary = ink.opacity(secondaryAlpha)
    /// Etichette di unità e didascalie. Il pavimento, non un punto di partenza.
    public static let inkTertiary = ink.opacity(tertiaryAlpha)

    // MARK: Fondi

    /// Fondo dell'app in giorno di mare e fondo di riferimento per il contrasto.
    public static let seaHex: UInt32 = 0x061726
    /// Il fondo effettivo di una card di vetro: 5.5% di bianco sopra `sea`.
    /// È il caso peggiore per il contrasto, quindi è quello che i test controllano.
    public static let glassOverSeaHex: UInt32 = 0x0C1F2D

    public static let abyss = Color(hex: 0x030C14)
    public static let sea = Color(hex: seaHex)
    /// Il posto vuoto dove andrà una fotografia: un blu appena più chiaro del fondo,
    /// così il riquadro si vede senza fingere di essere un'immagine.
    ///
    /// Era anche la cima del gradiente statico, ed era a `0x0A2338`: a quel valore
    /// l'inchiostro terziario sopra una card di vetro stava a 4,44:1, sotto la
    /// soglia. Non se n'era accorto nessuno perché il test controllava `sea`, che è
    /// il fondo, e non la cima — dove le card stanno davvero.
    public static let seaHigh = Color(hex: 0x092032)

    /// Sfondo di schermata in navigazione, a notte fonda.
    ///
    /// È l'ancora delle 0 del cielo variabile, non una coppia di colori a parte:
    /// le schermate senza crociera (onboarding, importazione, diario) devono
    /// assomigliare all'app di notte, e due elenchi di colori si sarebbero separati
    /// alla prima modifica.
    public static var seaBackground: LinearGradient { seaSky[0].sky.gradient }

    /// Sfondo di schermata in porto, a notte fonda: le luci della banchina.
    public static var harbourBackground: LinearGradient { harbourSky[0].sky.gradient }

    // MARK: Il cielo che cambia
    //
    // Il fondo segue l'ora del giorno. Due vincoli lo tengono onesto.
    //
    // Primo: l'ora è quella **di bordo**, non quella del telefono. È il principio su
    // cui è costruita tutta l'app, e uno sfondo che si accende quando il tuo telefono
    // dice mezzogiorno mentre a bordo sono le sei del mattino sarebbe la stessa bugia
    // dei countdown sbagliati.
    //
    // Secondo — ed è il vincolo che decide tutti i numeri qui sotto — **la luminanza
    // ha un tetto**. Un inchiostro chiaro perde contrasto man mano che il fondo si
    // schiarisce: con `tertiaryAlpha` a 0.52, sopra una card di vetro, il fondo più
    // chiaro ammesso sta intorno a `#1F1F1F` di luminanza. Sopra quello le etichette
    // scendono sotto 4,5:1 e diventano illeggibili proprio col sole negli occhi.
    //
    // Da qui la forma di queste tabelle: il giro del giorno si fa **in tinta e in
    // saturazione**, non in luminosità. Le quattro ore hanno colori diversissimi fra
    // loro, ma tutte alla stessa (bassa) luminanza.
    //
    // I colori di mezzogiorno sono quelli che Matteo ha disegnato in Figma il 4
    // settembre 2026 — l'azzurro `#155B96` dell'Itinerario per il mare, il caldo
    // `#745535` della banchina per il porto — **scalati di un solo fattore per tutto
    // il gradiente** (0,356 e 0,343) finché ogni fermata tocca la soglia. Un fattore
    // per gradiente e non uno per fermata: scalando ogni fermata per conto suo tutte
    // finiscono alla stessa luminanza e il gradiente si appiattisce su un colore solo.
    //
    // Le tinte di mezzanotte sono state spostate al blu-violetto proprio per questo:
    // una volta scurito, il suo azzurro di giorno finiva addosso al blu di notte, e
    // con la luminosità bloccata la tinta è l'unica cosa che resta a distinguerli.

    /// Le tre fermate di uno sfondo di schermata.
    public struct Sky: Equatable, Sendable {
        public let top: UInt32
        public let middle: UInt32
        public let bottom: UInt32

        init(_ top: UInt32, _ middle: UInt32, _ bottom: UInt32) {
            (self.top, self.middle, self.bottom) = (top, middle, bottom)
        }

        public var stops: [UInt32] { [top, middle, bottom] }
        public var colors: [Color] { stops.map { Color(hex: $0) } }

        var gradient: LinearGradient {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }

        static func blend(_ a: Sky, _ b: Sky, _ t: Double) -> Sky {
            Sky(Palette.blend(a.top, b.top, t),
                Palette.blend(a.middle, b.middle, t),
                Palette.blend(a.bottom, b.bottom, t))
        }
    }

    /// Le quattro ancore del giorno, in mare.
    static let seaSky: [(hour: Double, sky: Sky)] = [
        (0,  Sky(0x141336, 0x061726, 0x030C14)),   // notte: indaco profondo
        (6,  Sky(0x2A1631, 0x061624, 0x04101A)),   // alba: il viola che precede il sole
        (12, Sky(0x072035, 0x051522, 0x05131F)),   // giorno: il suo azzurro, portato a norma
        (18, Sky(0x2D1722, 0x061624, 0x04101A))    // crepuscolo: il rosa che si spegne
    ]

    /// Le stesse quattro ore con la luce della banchina.
    static let harbourSky: [(hour: Double, sky: Sky)] = [
        (0,  Sky(0x17182E, 0x0B1725, 0x030C14)),   // notte: il molo al buio
        (6,  Sky(0x2E171B, 0x0A1725, 0x04101C)),   // alba: rosso mattone
        (12, Sky(0x281D12, 0x0A1725, 0x051524)),   // giorno: il suo ambra, portato a norma
        (18, Sky(0x2F1810, 0x0A1725, 0x04101C))    // tramonto: l'arancio che cala
    ]

    /// Lo sfondo all'ora di bordo data.
    public static func sky(hour: Double, inPort: Bool) -> Sky {
        let anchors = inPort ? harbourSky : seaSky
        let h = ((hour.truncatingRemainder(dividingBy: 24)) + 24)
            .truncatingRemainder(dividingBy: 24)
        for index in anchors.indices {
            let a = anchors[index]
            let b = anchors[(index + 1) % anchors.count]
            let end = b.hour > a.hour ? b.hour : b.hour + 24
            if h >= a.hour && h < end {
                return Sky.blend(a.sky, b.sky, (h - a.hour) / (end - a.hour))
            }
        }
        return anchors[0].sky
    }

    /// La fermata in cima, in esadecimale: serve ai test di continuità.
    public static func skyTopHex(hour: Double, inPort: Bool) -> UInt32 {
        sky(hour: hour, inPort: inPort).top
    }

    /// Tutte le fermate di tutte le ore. È l'elenco che il test del contrasto deve
    /// passare in rassegna: le card scorrono sopra il gradiente, quindi un'etichetta
    /// può finire sopra qualunque punto di esso, non solo sopra la cima.
    public static func allSkyStops(inPort: Bool) -> [UInt32] {
        (inPort ? harbourSky : seaSky).flatMap(\.sky.stops)
    }

    private static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func mix(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
            return UInt32((x + (y - x) * t).rounded())
        }
        return (mix(16) << 16) | (mix(8) << 8) | mix(0)
    }

    /// Lo sfondo di una schermata all'ora di bordo data.
    public static func background(hour: Double, inPort: Bool) -> LinearGradient {
        sky(hour: hour, inPort: inPort).gradient
    }

    // MARK: Accenti
    //
    // Nessuno di questi porta significato da solo (§J dell'audit): ogni stato che
    // li usa affianca sempre un glifo e una parola.

    /// In navigazione, dato fresco, tappa già fatta. 10.9:1 sul fondo.
    public static let underway = Color(hex: 0x46E0C0)
    /// In porto, all aboard, dato da confermare. 10.3:1 sul fondo.
    public static let ashore = Color(hex: 0xFFB454)
    /// Azioni e collegamenti.
    public static let action = Color(hex: 0x7FD8FF)
    /// Ritardo o discrepanza da segnalare senza allarmare.
    public static let adrift = Color(hex: 0xFF8A73)

    // MARK: Bordi

    public static let hairline = Color.white.opacity(0.14)
    public static let hairlineStrong = Color.white.opacity(0.24)
}

