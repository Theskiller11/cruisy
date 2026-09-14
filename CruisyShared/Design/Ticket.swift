import SwiftUI

// I componenti del biglietto: carta, perforazione, matrice, campi, timbro, pila.
//
// Sono i pezzi con cui l'app dice «documento di bordo». Stanno in CruisyShared
// perché li usano anche widget e Live Activity, che devono parlare la stessa lingua
// dell'app dentro i vincoli che hanno.

// MARK: - La forma del biglietto

/// Un rettangolo di carta con due incavi semicircolari ai lati, all'altezza della
/// perforazione: è quello che rende un rettangolo un biglietto.
///
/// Gli incavi sono **buchi** nella forma, non cerchi dipinti col colore del fondo:
/// così il biglietto sta su qualunque cosa — lo scafo, la scena del mare, la foto
/// di un porto — senza sapere cosa ha dietro.
public struct TicketShape: Shape {
    public var cornerRadius: CGFloat
    /// Dove passa la perforazione, dall'alto. Nulla = nessun incavo.
    public var perforationY: CGFloat?
    public var notchRadius: CGFloat

    public init(cornerRadius: CGFloat = 18, perforationY: CGFloat?, notchRadius: CGFloat = 11) {
        self.cornerRadius = cornerRadius
        self.perforationY = perforationY
        self.notchRadius = notchRadius
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        guard let y = perforationY, y > notchRadius, y < rect.height - notchRadius else { return path }
        // Sottratti con la regola pari/dispari: vedi `TicketPaper`.
        path.addEllipse(in: CGRect(x: rect.minX - notchRadius, y: rect.minY + y - notchRadius,
                                   width: notchRadius * 2, height: notchRadius * 2))
        path.addEllipse(in: CGRect(x: rect.maxX - notchRadius, y: rect.minY + y - notchRadius,
                                   width: notchRadius * 2, height: notchRadius * 2))
        return path
    }
}

/// La carta: bianca, con l'ombra di un cartoncino appoggiato sullo scafo.
///
/// Se `perforationY` è dato, la forma ha gli incavi; la misura la fornisce chi
/// impagina, leggendola dalla parte alta del biglietto.
struct TicketPaper: ViewModifier {
    @Environment(\.livery) private var livery
    var cornerRadius: CGFloat = 18
    var perforationY: CGFloat?

    func body(content: Content) -> some View {
        let shape = TicketShape(cornerRadius: cornerRadius, perforationY: perforationY)
        content
            .background(shape.fill(livery.paper, style: FillStyle(eoFill: true)))
            .clipShape(shape, style: FillStyle(eoFill: true))
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
    }
}

public extension View {
    /// Posa il contenuto su un biglietto di carta.
    func ticketPaper(cornerRadius: CGFloat = 18, perforationY: CGFloat? = nil) -> some View {
        modifier(TicketPaper(cornerRadius: cornerRadius, perforationY: perforationY))
    }
}

// MARK: - Il biglietto intero

/// Parte alta, perforazione, matrice: il biglietto composto.
///
/// La perforazione cade dove finisce la parte alta, misurata a impaginazione fatta:
/// così gli incavi stanno sempre sulla linea tratteggiata, a qualunque corpo di testo.
public struct Ticket<Top: View, Stub: View>: View {
    @Environment(\.livery) private var livery
    private let top: Top
    private let stub: Stub
    private let cornerRadius: CGFloat

    @State private var topHeight: CGFloat = 0

    public init(cornerRadius: CGFloat = 18, @ViewBuilder top: () -> Top, @ViewBuilder stub: () -> Stub) {
        self.top = top()
        self.stub = stub()
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        VStack(spacing: 0) {
            top
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { topHeight = $0 }
            Perforation()
            stub
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ticketPaper(cornerRadius: cornerRadius, perforationY: topHeight > 0 ? topHeight : nil)
    }
}

/// La linea tratteggiata fra biglietto e matrice.
public struct Perforation: View {
    @Environment(\.livery) private var livery

    public init() {}

    public var body: some View {
        Line()
            .stroke(livery.perforation, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            .frame(height: 1.5)
            .padding(.horizontal, 18)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

// MARK: - Campi

/// Un campo della matrice: etichetta sopra, valore sotto. «ATTRACCO / 09:00».
public struct TicketField: View {
    @Environment(\.livery) private var livery
    let label: String
    let value: String
    /// Come lo legge VoiceOver, quando l'abbreviazione non basterebbe.
    var spoken: String?
    /// Il valore in colore segnale: per il rientro a bordo.
    var isSignal = false

    public init(label: String, value: String, spoken: String? = nil, isSignal: Bool = false) {
        self.label = label
        self.value = value
        self.spoken = spoken
        self.isSignal = isSignal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).ticketFieldLabel(livery.field)
                .lineLimit(2)
            Text(value)
                .font(TicketType.fieldValue)
                .foregroundStyle(isSignal ? livery.signalInk : livery.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label): \(spoken ?? value)"))
    }
}

/// I campi in griglia: due per riga; uno per riga ai corpi accessibili, perché
/// stringere le colonne taglia i numeri e un numero spezzato non è più un numero.
public struct TicketMatrix: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let fields: [TicketField]
    var columns: Int = 2

    public init(fields: [TicketField], columns: Int = 2) {
        self.fields = fields
        self.columns = columns
    }

    public var body: some View {
        let perRow = typeSize.isAccessibilitySize ? 1 : columns
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(stride(from: 0, to: fields.count, by: perRow)), id: \.self) { start in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(start..<min(start + perRow, fields.count), id: \.self) { fields[$0] }
                    // Le celle che mancano tengono la colonna: se no l'ultimo valore
                    // si allarga e va fuori squadro con quelli della riga sopra.
                    ForEach(0..<max(0, perRow - min(perRow, fields.count - start)), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }
}

/// Una riga sottile sulla carta, fra due gruppi di campi.
public struct TicketRule: View {
    @Environment(\.livery) private var livery
    public init() {}
    public var body: some View {
        Rectangle().fill(livery.rule).frame(height: 1).accessibilityHidden(true)
    }
}

// MARK: - Timbro

/// Il timbro: un cerchio a doppio bordo, inclinato, con due righe di maiuscole.
///
/// È il vocabolario per gli stati — «IN PORTO», «A BORDO», «TENDER» — e per i
/// porti toccati nel Diario. Inclinato di dodici gradi perché un timbro dritto
/// sembra un'icona; il colore è quello del segnale, ma la parola c'è sempre.
public struct Stamp: View {
    @Environment(\.livery) private var livery
    @ScaledMetric(relativeTo: .caption2) private var scaledDiameter: CGFloat = 66
    let text: String
    var color: Color?
    var rotation: Double = -12
    /// Un diametro fisso: il testo si adatta al cerchio, non il contrario. Serve
    /// dove i timbri stanno in griglia e devono avere tutti la stessa misura.
    var diameter: CGFloat?

    /// La misura del testo alla sua larghezza naturale: nel modo adattivo il
    /// cerchio si allarga finché la parola più lunga ci sta intera. «DA IMBAR-CARE»
    /// col trattino, al primo giro, è il motivo: un timbro non spezza le parole.
    @State private var textSize: CGSize = .zero

    public init(_ text: String, color: Color? = nil, rotation: Double = -12, diameter: CGFloat? = nil) {
        self.text = text
        self.color = color
        self.rotation = rotation
        self.diameter = diameter
    }

    public var body: some View {
        let tint = color ?? livery.signal
        Group {
            if let diameter {
                // Fisso: il testo va a capo sulle parole e, se serve, si stringe.
                Text(text)
                    .font(TicketType.stamp)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(tint)
                    .frame(width: diameter - 18, height: diameter - 18)
                    .frame(width: diameter, height: diameter)
            } else {
                let size = max(min(scaledDiameter, 96), textSize.width + 24, textSize.height + 20)
                Text(text)
                    .font(TicketType.stamp)
                    .tracking(1)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { textSize = $0 }
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
            }
        }
        .overlay(Circle().stroke(tint, lineWidth: 2.2))
        .overlay(Circle().stroke(tint, lineWidth: 0.8).padding(3.5))
        .rotationEffect(.degrees(rotation))
        .accessibilityLabel(Text(text))
    }
}

/// Un piccolo timbro rettangolare, per una parola sola accanto a un titolo:
/// «OGGI», «DOMANI», «TOCCATO», «IN CORSO». Prende poco spazio, e resta un timbro.
public struct StampBadge: View {
    @Environment(\.livery) private var livery
    let text: String
    var color: Color?

    public init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        let tint = color ?? livery.signalInk
        Text(text)
            .font(TicketType.stamp)
            .tracking(0.8)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint, lineWidth: 1.2))
            .rotationEffect(.degrees(-4))
            .accessibilityLabel(Text(text))
    }
}

// MARK: - La pila

/// Il biglietto che si intravede dietro: il prossimo scalo.
///
/// Solo la costa alta, in carta più scura, con una riga di maiuscole. Si tocca
/// per aprire lo scalo, se chi lo usa lo collega.
public struct TicketBehind: View {
    @Environment(\.livery) private var livery
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(TicketType.fieldLabel)
            .tracking(TicketType.fieldTracking)
            .textCase(.uppercase)
            .foregroundStyle(livery.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(livery.paperShade))
            .padding(.horizontal, 14)
    }
}

// MARK: - Carta di servizio

/// Una card di carta per il contenuto che non è un biglietto: righe informative,
/// interruttori, foto. Stessa carta, stessi angoli, meno cerimonia.
struct PaperCard: ViewModifier {
    @Environment(\.livery) private var livery
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(livery.paper))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
    }
}

public extension View {
    func paperCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(PaperCard(cornerRadius: cornerRadius))
    }
}

/// Una riga su carta: glifo, titolo, sottotitolo, e la freccia solo se porta altrove.
public struct PaperRow<Trailing: View>: View {
    @Environment(\.livery) private var livery
    let glyph: String
    let title: String
    var subtitle: String?
    var glyphColor: Color?
    @ViewBuilder var trailing: () -> Trailing

    public init(glyph: String, title: String, subtitle: String? = nil, glyphColor: Color? = nil,
                @ViewBuilder trailing: @escaping () -> Trailing) {
        self.glyph = glyph
        self.title = title
        self.subtitle = subtitle
        self.glyphColor = glyphColor
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(glyphColor ?? livery.ink)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TicketType.rowTitle)
                    .foregroundStyle(livery.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.field)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .paperCard()
    }
}

public extension PaperRow where Trailing == EmptyView {
    init(glyph: String, title: String, subtitle: String? = nil, glyphColor: Color? = nil) {
        self.init(glyph: glyph, title: title, subtitle: subtitle, glyphColor: glyphColor) { EmptyView() }
    }
}

/// La freccia di navigazione su carta.
public struct PaperDisclosure: View {
    @Environment(\.livery) private var livery
    public init() {}
    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(livery.field)
            .accessibilityHidden(true)
    }
}

// MARK: - Sullo scafo

/// Una pastiglia bordata sullo scafo: «Mosso · 0,8 m», «28°», «Tender: no».
public struct HullChip: View {
    @Environment(\.livery) private var livery
    let text: String
    var glyph: String?

    public init(_ text: String, glyph: String? = nil) {
        self.text = text
        self.glyph = glyph
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let glyph {
                Image(systemName: glyph).font(.system(.caption, weight: .semibold))
            }
            Text(text).font(TicketType.chip)
        }
        .foregroundStyle(livery.onHull)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .overlay(Capsule().stroke(livery.onHull.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Un avviso sullo scafo: la nota che compare quando qualcosa va detto forte.
///
/// Carta, non vetro: sullo scafo blu un foglietto bianco si vede da lontano, che è
/// il motivo per cui esiste.
public struct HullNotice: View {
    @Environment(\.livery) private var livery
    let message: LocalizedStringKey
    var glyph = "exclamationmark.triangle.fill"

    public init(_ message: LocalizedStringKey, glyph: String = "exclamationmark.triangle.fill") {
        self.message = message
        self.glyph = glyph
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: glyph)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(livery.signalInk)
            Text(message)
                .font(TicketType.rowDetail)
                .foregroundStyle(livery.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .paperCard(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }
}

/// La testata sullo scafo: il nome della nave, e sotto il giorno.
public struct Masthead: View {
    @Environment(\.livery) private var livery
    let title: String
    var detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(TicketType.masthead)
                .tracking(TicketType.mastheadTracking)
                .textCase(.uppercase)
                .foregroundStyle(livery.onHull)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                // Un'ombra morbida: sul cielo del giorno di mare il bianco poggia
                // sullo zenit, che resta scuro a ogni ora, ma l'ombra lo tiene
                // leggibile anche dove passa il sole.
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            if let detail {
                Text(detail)
                    .font(TicketType.mastheadDetail)
                    .tracking(TicketType.eyebrowTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.onHull.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
