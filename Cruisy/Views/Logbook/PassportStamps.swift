import SwiftUI

/// Il timbro di un porto, come sul passaporto: una forma e un inchiostro suoi, il
/// nome, la data.
///
/// Prima erano tutti cerchi grigi uguali, e una pagina di quattro cerchi grigi non
/// si ricorda. Qui ogni porto ha sempre lo stesso timbro (`StampStyle`,
/// `StampInk`), così Gustavia si riconosce prima di leggerla.
struct PassportStamp: View {
    enum Kind { case arrival, embarkation }

    @Environment(\.livery) private var livery
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1
    let name: String
    let date: Date
    let clock: ShipClock
    var visits = 1
    var kind: Kind = .arrival
    var rotation: Double = -8

    private var style: StampStyle { StampStyle.of(name) }
    private var ink: Color { livery.stampInk(StampInk.of(name)) }

    /// La misura del timbro: cresce col testo fino a un tetto, poi il testo si stringe.
    private var size: CGSize {
        let grow = min(scale, 1.35)
        switch style {
        case .round, .octagon: return CGSize(width: 104 * grow, height: 104 * grow)
        case .framed: return CGSize(width: 128 * grow, height: 78 * grow)
        case .oval: return CGSize(width: 134 * grow, height: 84 * grow)
        }
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(kind == .embarkation ? "Imbarco" : "Arrivo")
                .font(.system(size: 7.5 * min(scale, 1.35), weight: .heavy))
                .tracking(1.2)
                .textCase(.uppercase)
            Text(Self.lines(name))
                .font(.system(size: 14 * min(scale, 1.35), weight: .black).width(.condensed))
                .tracking(0.6)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.55)
            Rectangle().frame(width: size.width * 0.34, height: 0.8).padding(.vertical, 1)
            Text(dateLabel)
                .font(.system(size: 8 * min(scale, 1.35), weight: .heavy).monospacedDigit())
                .tracking(0.6)
        }
        .foregroundStyle(ink)
        .padding(style == .framed ? 10 : 16)
        .frame(width: size.width, height: size.height)
        .background { border }
        .opacity(0.92)
        .rotationEffect(.degrees(rotation))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .round:
            ZStack {
                Circle().stroke(ink, lineWidth: 2.2)
                Circle().stroke(ink, lineWidth: 0.8).padding(5)
            }
        case .framed:
            ZStack {
                RoundedRectangle(cornerRadius: 6).stroke(ink, lineWidth: 2.2)
                RoundedRectangle(cornerRadius: 3).stroke(ink, lineWidth: 0.8).padding(5)
            }
        case .oval:
            ZStack {
                Ellipse().stroke(ink, lineWidth: 2.2)
                Ellipse().stroke(ink, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2])).padding(5)
            }
        case .octagon:
            ZStack {
                Octagon().stroke(ink, lineWidth: 2.2)
                Octagon().stroke(ink, lineWidth: 0.8).padding(6)
            }
        }
    }

    /// «25 SET 2026», nell'ora di bordo di quella crociera.
    private var dateLabel: String {
        var style = Date.FormatStyle().day().month(.abbreviated).year()
        style.timeZone = clock.timeZone(at: date)
        var text = date.formatted(style).uppercased().replacingOccurrences(of: ".", with: "")
        if visits > 1 { text += " · ×\(visits)" }
        return text
    }

    private var spoken: String {
        var parts = [name, date.formatted(date: .long, time: .omitted)]
        if kind == .embarkation { parts.insert(String(localized: "imbarco"), at: 1) }
        if visits > 1 { parts.append(String(localized: "\(visits) volte")) }
        return parts.joined(separator: ", ")
    }

    /// Il nome spezzato sulle parole: due parole corte stanno sulla stessa riga,
    /// «SAN JUAN», non «SAN / JUAN».
    static func lines(_ name: String) -> String {
        var lines: [String] = []
        for word in name.split(separator: " ").map(String.init) {
            if let last = lines.last, last.count + word.count + 1 <= 10 {
                lines[lines.count - 1] = last + " " + word
            } else {
                lines.append(word)
            }
        }
        return lines.prefix(3).joined(separator: "\n")
    }
}

private struct Octagon: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(rect.width, rect.height) * 0.29
        var path = Path()
        path.addLines([
            CGPoint(x: rect.minX + cut, y: rect.minY), CGPoint(x: rect.maxX - cut, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + cut), CGPoint(x: rect.maxX, y: rect.maxY - cut),
            CGPoint(x: rect.maxX - cut, y: rect.maxY), CGPoint(x: rect.minX + cut, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - cut), CGPoint(x: rect.minX, y: rect.minY + cut),
        ])
        path.closeSubpath()
        return path
    }
}

/// Una pagina di passaporto: la carta con la filigrana e i timbri, due per riga,
/// inclinati ognuno a modo suo e un po' accavallati.
struct PassportPage: View {
    struct Entry: Identifiable {
        var name: String
        var date: Date
        var clock: ShipClock
        var visits: Int
        var kind: PassportStamp.Kind
        var id: String { "\(name)|\(date.timeIntervalSince1970)" }
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    let entries: [Entry]

    var body: some View {
        // Ai corpi accessibili un timbro per riga: due affiancati uscirebbero dalla carta.
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns),
                  spacing: -4) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                // Inclinazioni diverse ma **fisse**: un timbro che gira a ogni
                // ridisegno non è un timbro.
                PassportStamp(name: entry.name, date: entry.date, clock: entry.clock,
                              visits: entry.visits, kind: entry.kind,
                              rotation: [-10.0, 6, 5, -8, 9, -5][index % 6])
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .offset(y: index % 2 == 1 && columns == 2 ? 8 : 0)
            }
        }
    }
}

/// La filigrana della carta del passaporto: onde sottili, come sulla carta valori.
struct Guilloche: View {
    @Environment(\.livery) private var livery

    var body: some View {
        Canvas { context, size in
            let rows = max(3, Int(size.height / 26))
            for row in 0..<rows {
                let y0 = CGFloat(row) * size.height / CGFloat(rows) + 13
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y0))
                var x: CGFloat = 0
                while x <= size.width {
                    path.addLine(to: CGPoint(x: x, y: y0 + 3.5 * sin(x / 17 + CGFloat(row))))
                    x += 4
                }
                context.stroke(path, with: .color(livery.perforation.opacity(0.35)), lineWidth: 0.6)
            }
        }
        .accessibilityHidden(true)
    }
}
