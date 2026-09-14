import SwiftUI

/// La scala tipografica di Cruisy, tutta agganciata al Dynamic Type.
///
/// Il brief fissava i corpi in pixel, e le etichette stavano a 9–10.5px: sotto il
/// minimo iOS (`caption2` = 11pt) e immobili al variare delle preferenze di testo.
/// Qui ogni stile parte da un text style di sistema, quindi scala da solo.
public enum Type {

    /// Titolo di schermata — "La mia crociera", "Itinerario".
    public static let screenTitle = Font.title3.weight(.semibold)
    /// Riga sotto il titolo — "Explora III · giorno 4 di 9".
    public static let screenSubtitle = Font.footnote.weight(.medium)

    /// Titolo di una card o di una riga di elenco.
    public static let rowTitle = Font.subheadline.weight(.semibold)
    /// Riga di appoggio dentro una card.
    public static let rowDetail = Font.caption.weight(.medium)

    /// Il valore di una metrica: 18,4 kt, 287°, 218 mn.
    public static let metricValue = Font.body.weight(.semibold).monospacedDigit()
    /// L'etichetta sotto una metrica. `caption2` è il pavimento: mai più piccolo.
    public static let metricLabel = Font.caption2.weight(.medium)

    /// Etichette maiuscole spaziate — "IN NAVIGAZIONE", "ALL ABOARD".
    public static let eyebrow = Font.caption2.weight(.semibold)
    /// Dati tecnici: coordinate, MMSI, ore di aggiornamento.
    public static let technical = Font.caption2.weight(.medium).monospaced()

    /// Tracking: negativo sui corpi grandi, neutro sul testo corrente, positivo
    /// sulle maiuscolette. Un solo valore per tutte le misure sarebbe sbagliato
    /// da qualche parte.
    public static let displayTracking: CGFloat = -1.4
    public static let titleTracking: CGFloat = -0.3
    public static let eyebrowTracking: CGFloat = 0.9
}

/// Il countdown: grande, a cifre di larghezza fissa, e scalato col Dynamic Type
/// ma con un tetto.
///
/// Il tetto serve perché a AX5 un corpo da 52pt diventerebbe ~120pt e sfonderebbe
/// la card. Si scala l'altezza, non si sfonda la larghezza — la lezione già pagata
/// su MeteoConsenso.
public struct DisplayNumeral: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var scaled: CGFloat = 52
    private let cap: CGFloat

    public init(size: CGFloat, cap: CGFloat) {
        self._scaled = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
        self.cap = cap
    }

    public func body(content: Content) -> some View {
        content
            .font(.system(size: min(scaled, cap), weight: .semibold, design: .default))
            .monospacedDigit()
            .tracking(Type.displayTracking)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

public extension View {
    /// Corpo da display per i numeri che contano, con tetto di scalatura.
    func displayNumeral(size: CGFloat, cap: CGFloat) -> some View {
        modifier(DisplayNumeral(size: size, cap: cap))
    }

    /// Maiuscoletto spaziato per le etichette di sezione.
    func eyebrow(_ color: Color = Palette.inkTertiary) -> some View {
        self.font(Type.eyebrow)
            .tracking(Type.eyebrowTracking)
            .foregroundStyle(color)
            .textCase(.uppercase)
    }
}
