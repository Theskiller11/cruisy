import SwiftUI

/// Il cielo sopra la nave, all'ora di bordo.
///
/// Due colori — lo zenit in alto, l'orizzonte in basso — e il sole o la luna dove
/// stanno a quell'ora. L'ora è **di bordo**, non del telefono: un cielo che si
/// accende quando il telefono dice mezzogiorno mentre a bordo sono le sei sarebbe
/// la stessa bugia dei countdown sbagliati.
///
/// Lo zenit resta scuro a **ogni** ora, ed è verificato da `SeaSceneContrastTests`:
/// è lì che poggia la testata con il nome della nave, e il bianco deve leggersi
/// anche a mezzogiorno. L'orizzonte invece può accendersi quanto vuole — rosa
/// all'alba, arancio al tramonto, celeste di giorno — perché sopra non c'è testo:
/// il biglietto di carta copre la linea dell'orizzonte, e il testo sta sulla carta.
public struct SeaSky: Equatable, Sendable {
    public let zenith: UInt32
    public let horizon: UInt32

    init(_ zenith: UInt32, _ horizon: UInt32) {
        self.zenith = zenith
        self.horizon = horizon
    }

    /// Le ancore del giro del giorno, in ora di bordo.
    static let anchors: [(hour: Double, sky: SeaSky)] = [
        (0,  SeaSky(0x05101F, 0x0F2A47)),   // notte fonda: quasi nero, blu all'orizzonte
        (5,  SeaSky(0x0A1A38, 0x2B3A66)),   // prima dell'alba
        (6.5, SeaSky(0x1D3560, 0xE9A36A)),  // alba: arancio basso
        (9,  SeaSky(0x1D62A6, 0x9CD1F2)),   // mattina
        (13, SeaSky(0x1B5EA3, 0xA9DBF7)),   // pieno giorno
        (17, SeaSky(0x2A4D86, 0xE8B07A)),   // pomeriggio che cala
        (18.5, SeaSky(0x2B2A5A, 0xEF7E56)), // tramonto
        (20, SeaSky(0x0F1B3C, 0x4A3A64)),   // crepuscolo
        (22, SeaSky(0x07142A, 0x1A2E50)),   // sera
    ]

    /// Il cielo a un'ora, interpolando fra le ancore.
    public static func at(hour: Double) -> SeaSky {
        let h = ((hour.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        for index in anchors.indices {
            let a = anchors[index]
            let b = anchors[(index + 1) % anchors.count]
            let end = b.hour > a.hour ? b.hour : b.hour + 24
            if h >= a.hour && h < end {
                let t = (h - a.hour) / (end - a.hour)
                return SeaSky(blend(a.sky.zenith, b.sky.zenith, t), blend(a.sky.horizon, b.sky.horizon, t))
            }
        }
        return anchors[0].sky
    }

    private static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func mix(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
            return UInt32((x + (y - x) * t).rounded())
        }
        return (mix(16) << 16) | (mix(8) << 8) | mix(0)
    }

    // MARK: Sole e luna

    public static let sunrise: Double = 6
    public static let sunset: Double = 18.5

    /// Dove sta il sole, da 0 (sorge a sinistra) a 1 (tramonta a destra); nullo di notte.
    public static func sunProgress(hour: Double) -> Double? {
        guard hour >= sunrise, hour <= sunset else { return nil }
        return (hour - sunrise) / (sunset - sunrise)
    }

    /// Dove sta la luna, nello stesso modo; nulla di giorno.
    public static func moonProgress(hour: Double) -> Double? {
        guard sunProgress(hour: hour) == nil else { return nil }
        let night = 24 - (sunset - sunrise)
        let since = hour > sunset ? hour - sunset : hour + 24 - sunset
        return since / night
    }
}

/// La scena del giorno di mare: cielo, sole o luna, e le onde che si muovono.
///
/// Sta dietro al biglietto verso il prossimo scalo, e finisce nel colore dello
/// scafo: sotto le onde la schermata continua senza giunture.
///
/// **Riduci movimento** ferma le onde e lascia la scena immobile. Fuori dal primo
/// piano l'animazione si sospende: `TimelineView(.animation(paused:))` smette di
/// chiedere fotogrammi, che è l'unico modo perché non costi batteria in tasca.
public struct SeaScene: View {
    @Environment(\.livery) private var livery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// L'ora di bordo, decimale.
    let hour: Double

    public init(hour: Double) { self.hour = hour }

    private var isPaused: Bool { reduceMotion || scenePhase != .active }

    public var body: some View {
        let sky = SeaSky.at(hour: hour)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isPaused)) { context in
            let time = isPaused ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true, rendersAsynchronously: false) { canvas, size in
                draw(sky: sky, time: time, in: &canvas, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(sky: SeaSky, time: TimeInterval, in canvas: inout GraphicsContext, size: CGSize) {
        // La linea dell'orizzonte sta a tre quinti: sopra il cielo, sotto il mare.
        let horizonY = size.height * 0.6
        let skyRect = CGRect(x: 0, y: 0, width: size.width, height: horizonY + 2)

        // Il cielo **parte dallo scafo**: in cima è del colore della schermata e
        // scende verso lo zenit, poi verso l'orizzonte. Così la scena non ha un
        // bordo superiore — il blu della testata è il cielo che si fa profondo — e
        // sopra di lei non c'è mai testo da tenere a contrasto.
        canvas.fill(Path(skyRect), with: .linearGradient(
            Gradient(stops: [.init(color: livery.hull, location: 0),
                             .init(color: Color(hex: sky.zenith), location: 0.3),
                             .init(color: Color(hex: sky.horizon), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: horizonY)))

        drawStars(in: &canvas, size: size, horizonY: horizonY)
        drawCelestial(in: &canvas, size: size, horizonY: horizonY)
        drawSea(in: &canvas, size: size, horizonY: horizonY, time: time, sky: sky)
    }

    /// Le stelle: poche, ferme, solo quando il cielo è scuro davvero.
    private func drawStars(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat) {
        guard SeaSky.sunProgress(hour: hour) == nil else { return }
        // Posizioni fisse, ricavate da una sequenza deterministica: stelle che
        // cambiano posto a ogni ridisegno sarebbero uno sfarfallio.
        var seed: UInt32 = 2_463_534_242
        func next() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return CGFloat(seed % 10_000) / 10_000
        }
        for _ in 0..<28 {
            let x = next() * size.width
            let y = next() * horizonY * 0.8
            let r = 0.6 + next() * 1.1
            canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(0.55 + Double(next()) * 0.4)))
        }
    }

    /// Il sole di giorno, la luna di notte, lungo un arco basso.
    private func drawCelestial(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat) {
        let sun = SeaSky.sunProgress(hour: hour)
        let progress = sun ?? SeaSky.moonProgress(hour: hour) ?? 0
        // L'arco: sorge a sinistra sull'orizzonte, culmina in alto, tramonta a destra.
        let x = size.width * (0.08 + 0.84 * progress)
        let y = horizonY - sin(progress * .pi) * (horizonY * 0.66) + 6
        let radius: CGFloat = sun != nil ? 22 : 16
        let disc = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))

        if sun != nil {
            canvas.fill(Path(ellipseIn: CGRect(x: x - radius * 2.2, y: y - radius * 2.2,
                                               width: radius * 4.4, height: radius * 4.4)),
                        with: .color(Color(hex: 0xFFE9A8).opacity(0.22)))
            canvas.fill(disc, with: .color(Color(hex: 0xFFEDB3)))
        } else {
            canvas.fill(disc, with: .color(Color(hex: 0xE8ECF3)))
            // Il quarto d'ombra: una luna piena ogni notte sembrerebbe un sole spento.
            let shadow = Path(ellipseIn: CGRect(x: x - radius * 0.55, y: y - radius * 1.05,
                                                width: radius * 2, height: radius * 2.1))
            canvas.fill(shadow, with: .color(Color(hex: 0x0A1A38).opacity(0.9)))
        }
    }

    /// Tre onde, una sopra l'altra, che scorrono a velocità diverse: l'ultima è
    /// dello stesso colore dello scafo e chiude la scena senza giunture.
    private func drawSea(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat,
                         time: TimeInterval, sky: SeaSky) {
        let layers: [(offset: CGFloat, amplitude: CGFloat, wavelength: CGFloat, speed: Double, color: Color)] = [
            (0, 5, 190, 0.35, Color(hex: sky.horizon).opacity(0.55).blended(over: livery.hull, 0.5)),
            (16, 7, 140, 0.55, livery.onHull.opacity(0.10).blended(over: livery.hull, 1)),
            (34, 9, 110, 0.8, livery.hull),
        ]
        for (index, layer) in layers.enumerated() {
            // La nave passa fra la prima onda e la seconda: la prua nell'acqua.
            if index == 1 { drawShip(in: &canvas, size: size, horizonY: horizonY, time: time) }
            var path = Path()
            let baseY = horizonY + layer.offset
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: baseY))
            var x: CGFloat = 0
            let phase = time * layer.speed
            while x <= size.width + 4 {
                let y = baseY + sin(Double(x) / Double(layer.wavelength) * 2 * .pi + phase) * Double(layer.amplitude)
                path.addLine(to: CGPoint(x: x, y: y))
                x += 4
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            canvas.fill(path, with: .color(layer.color))
        }
    }

    /// Una nave di profilo che attraversa la scena, piano, e beccheggia con l'onda.
    ///
    /// È la parte che «diverte»: sei punti al secondo, un giro ogni minuto e mezzo,
    /// e con Riduci movimento sta ferma a un terzo della scena. Nessuna livrea di
    /// nessuna compagnia: scafo scuro, sovrastruttura bianca, un fumaiolo.
    private func drawShip(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat,
                          time: TimeInterval) {
        let span = size.width + 140
        let x = time == 0 ? size.width * 0.34
                          : (CGFloat(time * 6).truncatingRemainder(dividingBy: span)) - 70
        let bob = time == 0 ? 0 : sin(time * 0.9) * 1.6
        let y = horizonY + 9 + bob
        let tilt = time == 0 ? 0 : sin(time * 0.9 + 0.6) * 0.02

        var hull = Path()
        hull.move(to: CGPoint(x: -34, y: 0))
        hull.addLine(to: CGPoint(x: 36, y: 0))
        hull.addLine(to: CGPoint(x: 30, y: 9))
        hull.addLine(to: CGPoint(x: -30, y: 9))
        hull.closeSubpath()

        var deck = Path()
        deck.addRoundedRect(in: CGRect(x: -24, y: -14, width: 44, height: 14), cornerSize: CGSize(width: 2, height: 2))
        deck.addRoundedRect(in: CGRect(x: -16, y: -22, width: 26, height: 8), cornerSize: CGSize(width: 2, height: 2))
        var funnel = Path()
        funnel.addRect(CGRect(x: 4, y: -30, width: 6, height: 9))

        let transform = CGAffineTransform(translationX: x, y: y).rotated(by: tilt)
        canvas.fill(hull.applying(transform), with: .color(livery.hullDeep))
        canvas.fill(deck.applying(transform), with: .color(Color(hex: 0xF2F5F8)))
        canvas.fill(funnel.applying(transform), with: .color(livery.signal))
        // Le finestre: una fila di punti, che a questa scala bastano.
        var windows = Path()
        for i in 0..<7 {
            windows.addEllipse(in: CGRect(x: -20 + CGFloat(i) * 6, y: -9, width: 2.2, height: 2.2))
        }
        canvas.fill(windows.applying(transform), with: .color(livery.hullDeep.opacity(0.7)))
    }
}

private extension Color {
    /// Questo colore appoggiato su un altro, con l'opacità data: un colore pieno,
    /// così le onde non lasciano trasparire quello che c'è sotto.
    func blended(over base: Color, _ alpha: Double) -> Color {
        let a = UIColor(self).resolved, b = UIColor(base).resolved
        let t = a.alpha * alpha
        return Color(.sRGB, red: a.red * t + b.red * (1 - t),
                     green: a.green * t + b.green * (1 - t),
                     blue: a.blue * t + b.blue * (1 - t), opacity: 1)
    }
}

private extension UIColor {
    var resolved: (red: Double, green: Double, blue: Double, alpha: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
