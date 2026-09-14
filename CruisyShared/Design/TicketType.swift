import SwiftUI

/// La tipografia del biglietto: stretta e nera per le ore, normale per il resto.
///
/// Il riferimento della direzione D era Archivo, un grottesco con l'asse della
/// larghezza. Qui si usa **il carattere di sistema con l'asse della larghezza**, che
/// è la stessa idea senza un file da includere: SF Pro ha le larghezze compressed,
/// condensed ed expanded, segue Dynamic Type da solo, e non pone nessuna domanda di
/// licenza. Il biglietto vive del contrasto fra stretto e largo, e quello c'è.
///
/// Ogni stile parte da un text style di sistema, così scala con le preferenze di
/// testo. Le sole misure in punti sono quelle dei numeri da display, che passano da
/// `@ScaledMetric` con un tetto: si scala l'altezza, non si sfonda la larghezza.
public enum TicketType {

    /// Il nome della nave in testa alla schermata: stretto, nero, maiuscolo.
    public static let masthead = Font.system(.title, design: .default, weight: .heavy).width(.condensed)
    /// La riga sotto il nome: «GIORNO 5 DI 9».
    public static let mastheadDetail = Font.system(.footnote, weight: .semibold).width(.condensed)

    /// L'etichetta sopra l'ora: «RIENTRO A BORDO».
    public static let eyebrow = Font.system(.caption, weight: .bold)
    /// Dove: «PUERTO PLATA · AMBER COVE».
    public static let place = Font.system(.subheadline, weight: .bold).width(.condensed)

    /// L'etichetta di un campo della matrice: «ATTRACCO».
    public static let fieldLabel = Font.system(.caption2, weight: .bold)
    /// Il valore di un campo: «09:00», «9 h», «Pubblicato».
    public static let fieldValue = Font.system(.body, weight: .bold).monospacedDigit()

    /// Il countdown nella matrice: stretto e nero, ma meno dell'ora.
    public static let count = Font.system(.title, design: .default, weight: .black)
        .width(.condensed).monospacedDigit()

    /// Il testo dentro un timbro.
    public static let stamp = Font.system(.caption2, weight: .black)

    /// Testo corrente sulla carta: descrizioni, note.
    public static let body = Font.system(.subheadline)
    /// Titolo di una riga su carta.
    public static let rowTitle = Font.system(.subheadline, weight: .semibold)
    /// Riga di appoggio.
    public static let rowDetail = Font.system(.footnote)
    /// Dati tecnici: coordinate, MMSI.
    public static let technical = Font.system(.caption, design: .monospaced, weight: .medium)

    /// Le pastiglie sullo scafo: «Mosso · 0,8 m», «28°».
    public static let chip = Font.system(.footnote, weight: .semibold)

    /// Spaziatura delle maiuscolette: positiva, come su un modulo stampato.
    public static let eyebrowTracking: CGFloat = 1.4
    public static let fieldTracking: CGFloat = 1.1
    public static let mastheadTracking: CGFloat = 0.4
}

/// L'ora stampata grande: «17:30». Compressed, nera, scalata col Dynamic Type ma
/// con un tetto, se no ad AX5 sfonderebbe il biglietto.
public struct TicketHour: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var scaled: CGFloat = 84
    private let cap: CGFloat

    public init(size: CGFloat, cap: CGFloat) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
        self.cap = cap
    }

    public func body(content: Content) -> some View {
        content
            .font(.system(size: min(scaled, cap), weight: .black).width(.compressed))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// Un numero da display che non è un'ora: i giorni all'imbarco, le miglia.
public struct TicketNumeral: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var scaled: CGFloat = 64
    private let cap: CGFloat

    public init(size: CGFloat, cap: CGFloat) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
        self.cap = cap
    }

    public func body(content: Content) -> some View {
        content
            .font(.system(size: min(scaled, cap), weight: .black).width(.condensed))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

public extension View {
    /// L'ora grande del biglietto.
    func ticketHour(size: CGFloat = 84, cap: CGFloat = 112) -> some View {
        modifier(TicketHour(size: size, cap: cap))
    }

    /// Un numero grande che non è un'ora.
    func ticketNumeral(size: CGFloat = 64, cap: CGFloat = 96) -> some View {
        modifier(TicketNumeral(size: size, cap: cap))
    }

    /// L'etichetta sopra l'ora, nel colore dato.
    func ticketEyebrow(_ color: Color) -> some View {
        self.font(TicketType.eyebrow)
            .tracking(TicketType.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// L'etichetta di un campo della matrice.
    func ticketFieldLabel(_ color: Color) -> some View {
        self.font(TicketType.fieldLabel)
            .tracking(TicketType.fieldTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
