import Foundation

/// Matematica di contrasto WCAG 2.1, pura e senza dipendenze da UIKit, così i test
/// possono verificare la palette senza far girare l'interfaccia.
///
/// Esiste perché l'audit del brief ha trovato etichette a ~1.6:1 (`rgba(234,242,248,.32)`
/// su fondo scuro). La regola di Apple sui materiali traslucidi dice l'opposto: sopra
/// il vetro il testo va reso *più* contrastato, non più tenue. Qui il vincolo è
/// verificabile, non affidato all'occhio.
public enum Contrast {

    /// Componenti sRGB in 0…1.
    public struct RGB: Equatable, Sendable {
        public var r: Double, g: Double, b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { (self.r, self.g, self.b) = (r, g, b) }

        /// Da esadecimale a 24 bit, es. `0x46E0C0`.
        public init(hex: UInt32) {
            self.init(Double((hex >> 16) & 0xFF) / 255,
                      Double((hex >> 8) & 0xFF) / 255,
                      Double(hex & 0xFF) / 255)
        }
    }

    /// Compositing sorgente-sopra in spazio gamma sRGB, che è ciò che fa il compositor.
    public static func composite(_ foreground: RGB, over background: RGB, alpha: Double) -> RGB {
        let a = min(max(alpha, 0), 1)
        return RGB(foreground.r * a + background.r * (1 - a),
                   foreground.g * a + background.g * (1 - a),
                   foreground.b * a + background.b * (1 - a))
    }

    /// Luminanza relativa WCAG.
    public static func relativeLuminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// Rapporto di contrasto, da 1:1 a 21:1.
    public static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        let (hi, lo) = la > lb ? (la, lb) : (lb, la)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Contrasto di un testo a opacità `alpha` sopra `background`.
    public static func ratio(ofInk ink: RGB, atAlpha alpha: Double, over background: RGB) -> Double {
        ratio(composite(ink, over: background, alpha: alpha), background)
    }

    /// Soglie WCAG AA.
    public static let bodyMinimum = 4.5      // testo normale
    public static let largeTextMinimum = 3.0 // ≥ 24px, o ≥ 19px bold
    public static let nonTextMinimum = 3.0   // bordi e glifi portanti
}
