import SwiftUI

/// Il cielo sopra la nave, all'ora di bordo.
///
/// Due colori — lo zenit in alto, l'orizzonte in basso — e il sole o la luna dove
/// stanno a quell'ora. L'ora è **di bordo**, non del telefono: un cielo che si
/// accende quando il telefono dice mezzogiorno mentre a bordo sono le sei sarebbe
/// la stessa bugia dei countdown sbagliati.
///
/// Di giorno il cielo è **chiaro e luminoso**, all'alba e al tramonto caldo, di notte
/// scuro con la luna. Sopra la scena non c'è testo: la testata con il nome della
/// nave sta sullo scafo, sopra la fascia, e il resto sta sulla carta del biglietto.
/// Così il contrasto non dipende mai dal cielo, e il cielo può essere quello che è.
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
        (6.5, SeaSky(0x2E4A80, 0xF4A15C)),  // alba: arancio basso, cielo che si apre
        (8,  SeaSky(0x2F7BC7, 0xA8D8F5)),   // mattina
        (10, SeaSky(0x2F8AE0, 0xC6E6F9)),   // tarda mattina
        (13, SeaSky(0x3A93E6, 0xCDEBFA)),   // pieno giorno: chiaro e luminoso
        (16, SeaSky(0x3A83CC, 0xC0DCF0)),   // pomeriggio
        (17.5, SeaSky(0x3F5F9E, 0xF7B36A)), // il sole che cala
        (18.5, SeaSky(0x3A2F66, 0xF07C4E)), // tramonto
        (20, SeaSky(0x121C40, 0x4A3A64)),   // crepuscolo
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
        Livery.mix(a, b, t)
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

/// La scena del giorno di mare: cielo, sole o luna, nuvole, e il mare con la nave.
///
/// Sta dietro al biglietto verso il prossimo scalo, e finisce nel colore dello
/// scafo: sotto le onde la schermata continua senza giunture.
///
/// Rifatta il 24 settembre 2026. Il mare andava bene; il sole era un disco piatto
/// con un alone slavato e la nave una scatola grigia. Adesso il sole ha un alone
/// che respira e si scalda verso l'orizzonte, e il suo riflesso luccica sull'acqua;
/// la luna è una falce vera, ritagliata, non un disco scuro appoggiato sopra; le
/// nuvole passano lente, le stelle brillano a ritmi diversi, e la nave è quella di
/// `CruiseShipDrawing`, la stessa dell'onboarding.
///
/// Tutto è funzione dello stesso istante, dentro un `Canvas`: niente `withAnimation`,
/// che su un `Canvas` produce scatti. **Riduci movimento** ferma il tempo e lascia la
/// scena immobile. Fuori dal primo piano l'animazione si sospende:
/// `TimelineView(.animation(paused:))` smette di chiedere fotogrammi, che è l'unico
/// modo perché non costi batteria in tasca.
public struct SeaScene: View {
    @Environment(\.livery) private var livery
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Lo scafo nella modalità in vigore: le onde si mescolano con lui, e un `Canvas`
    /// vuole numeri, non colori dinamici.
    private var hullHex: UInt32 { livery.hullPair.hex(colorScheme == .dark ? .dark : .light) }

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

    // MARK: La scena

    /// Il sole o la luna: dove sta, quanto è grande, e quanto è vicino all'orizzonte.
    private struct Light {
        let center: CGPoint
        let radius: CGFloat
        let isSun: Bool
        /// Da 0, alto nel cielo, a 1, sull'orizzonte: scalda il sole e il suo riflesso.
        let low: Double
    }

    private func light(size: CGSize, horizonY: CGFloat) -> Light {
        let sun = SeaSky.sunProgress(hour: hour)
        let progress = sun ?? SeaSky.moonProgress(hour: hour) ?? 0
        // L'arco: sorge a sinistra sull'orizzonte, culmina in alto, tramonta a destra.
        let x = size.width * (0.08 + 0.84 * progress)
        let height = sin(progress * .pi)
        let y = horizonY - height * (horizonY * 0.66) + 6
        return Light(center: CGPoint(x: x, y: y), radius: sun != nil ? 15 : 12,
                     isSun: sun != nil, low: 1 - min(1, height / 0.45))
    }

    private func draw(sky: SeaSky, time: TimeInterval, in canvas: inout GraphicsContext, size: CGSize) {
        // La linea dell'orizzonte sta a tre quinti: sopra il cielo, sotto il mare.
        let horizonY = size.height * 0.6
        // Il cielo scende sotto l'orizzonte: dove la prima onda si abbassa, sotto ci
        // dev'essere cielo. Con due punti soli, lì si vedeva il fondo nero del `Canvas`,
        // una riga scura lungo tutto l'orizzonte.
        let skyRect = CGRect(x: 0, y: 0, width: size.width, height: horizonY + 24)

        // Il cielo **parte dallo scafo**: in cima è del colore della schermata e
        // scende verso lo zenit, poi verso l'orizzonte. Così la scena non ha un
        // bordo superiore — il blu della testata è il cielo che si fa profondo — e
        // sopra di lei non c'è mai testo da tenere a contrasto.
        canvas.fill(Path(skyRect), with: .linearGradient(
            Gradient(stops: [.init(color: Color(hex: hullHex), location: 0),
                             .init(color: Color(hex: sky.zenith), location: 0.28),
                             .init(color: Color(hex: sky.horizon), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: horizonY)))

        let light = light(size: size, horizonY: horizonY)
        drawStars(in: &canvas, size: size, horizonY: horizonY, time: time)
        if light.isSun { drawSun(light, in: &canvas, time: time) } else { drawMoon(light, in: &canvas) }
        drawClouds(in: &canvas, size: size, horizonY: horizonY, time: time, sky: sky, light: light)

        // L'orizzonte: una linea sottile di luce, che separa senza disegnare un bordo.
        var line = Path()
        line.move(to: CGPoint(x: 0, y: horizonY))
        line.addLine(to: CGPoint(x: size.width, y: horizonY))
        canvas.stroke(line, with: .color(.white.opacity(0.22)), lineWidth: 0.8)

        drawSea(in: &canvas, size: size, horizonY: horizonY, time: time, sky: sky, light: light)
    }

    // MARK: Il cielo

    /// Le stelle: poche, solo quando il cielo è scuro davvero, e ognuna brilla col
    /// suo ritmo.
    private func drawStars(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat, time: TimeInterval) {
        guard SeaSky.sunProgress(hour: hour) == nil else { return }
        // Posizioni fisse, ricavate da una sequenza deterministica: stelle che
        // cambiano posto a ogni ridisegno sarebbero uno sfarfallio.
        var seed: UInt32 = 2_463_534_242
        func next() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return CGFloat(seed % 10_000) / 10_000
        }
        for _ in 0..<32 {
            let x = next() * size.width
            let y = next() * horizonY * 0.82
            let r = 0.5 + next() * 1.1
            let base = 0.5 + Double(next()) * 0.35
            let rhythm = 0.6 + Double(next()) * 1.4, phase = Double(next()) * 6.3
            let twinkle = time == 0 ? base : base + 0.3 * sin(time * rhythm + phase)
            canvas.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(max(0.15, min(1, twinkle)))))
        }
    }

    /// Il sole: un nucleo caldo e un alone morbido che respira appena. Vicino
    /// all'orizzonte si fa arancio, come fa davvero.
    private func drawSun(_ light: Light, in canvas: inout GraphicsContext, time: TimeInterval) {
        let c = light.center, r = light.radius
        let breath = time == 0 ? 1 : 1 + 0.05 * sin(time * 0.9)
        let halo = r * 3.6 * breath
        let warm = Color(hex: Livery.mix(0xFFE59A, 0xFF9A4D, light.low))
        canvas.fill(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
                    with: .radialGradient(Gradient(stops: [
                        .init(color: warm.opacity(0.55), location: 0),
                        .init(color: warm.opacity(0.22), location: 0.35),
                        .init(color: warm.opacity(0), location: 1)]),
                        center: c, startRadius: 0, endRadius: halo))
        let core = Color(hex: Livery.mix(0xFFE08A, 0xFF8A3D, light.low))
        canvas.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(Gradient(colors: [Color(hex: 0xFFFDF2), core]),
                                          center: c, startRadius: 0, endRadius: r))
    }

    /// La luna: una falce vera, il disco meno un disco spostato. Il quarto d'ombra
    /// dipinto sopra col colore del cielo si vedeva come un disco scuro a parte.
    private func drawMoon(_ light: Light, in canvas: inout GraphicsContext) {
        let c = light.center, r = light.radius
        let halo = r * 3.4
        canvas.fill(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
                    with: .radialGradient(Gradient(stops: [
                        .init(color: Color(hex: 0xE8ECF6).opacity(0.28), location: 0),
                        .init(color: Color(hex: 0xE8ECF6).opacity(0), location: 1)]),
                        center: c, startRadius: 0, endRadius: halo))
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let bite = Path(ellipseIn: CGRect(x: c.x - r * 0.45, y: c.y - r * 1.2, width: r * 2, height: r * 2))
        canvas.fill(disc.subtracting(bite), with: .color(Color(hex: 0xEEF1F7)))
    }

    /// Le nuvole: tre, soffici, che attraversano in qualche minuto. Di giorno
    /// bianche, all'alba e al tramonto prendono il colore dell'orizzonte; di notte
    /// non ci sono, perché non si vedrebbero.
    private func drawClouds(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat,
                            time: TimeInterval, sky: SeaSky, light: Light) {
        guard light.isSun else { return }
        // Col sole basso le nuvole si fanno pesca, illuminate da sotto. Mescolate col
        // colore dell'orizzonte venivano grigio-lilla, spente contro il cielo viola.
        let tint = Color(hex: Livery.mix(0xFFFFFF, 0xFFB896, 0.75 * light.low))
        let opacity = 0.85
        let clouds: [(start: CGFloat, height: CGFloat, scale: CGFloat, speed: Double)] = [
            (0.62, 0.30, 1, 3.2), (0.18, 0.44, 0.72, 2.2), (0.9, 0.18, 0.55, 1.5),
        ]
        let span = size.width + 140
        for cloud in clouds {
            let drift = CGFloat(time * cloud.speed).truncatingRemainder(dividingBy: span)
            let x = (cloud.start * size.width + drift).truncatingRemainder(dividingBy: span) - 70
            let y = horizonY * cloud.height
            var puff = Path()
            let s = cloud.scale
            puff.addEllipse(in: CGRect(x: x - 26 * s, y: y - 8 * s, width: 52 * s, height: 16 * s))
            puff.addEllipse(in: CGRect(x: x - 22 * s, y: y - 14 * s, width: 26 * s, height: 16 * s))
            puff.addEllipse(in: CGRect(x: x - 5 * s, y: y - 18 * s, width: 30 * s, height: 20 * s))
            canvas.fill(puff, with: .color(tint.opacity(opacity)))
        }
    }

    // MARK: Il mare

    /// Tre onde, una sopra l'altra, che scorrono a velocità diverse: l'ultima è
    /// dello stesso colore dello scafo e chiude la scena senza giunture. Fra la
    /// prima e la seconda, il riflesso della luce e la nave.
    private func drawSea(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat,
                         time: TimeInterval, sky: SeaSky, light: Light) {
        // Il mare prende un po' del colore dell'orizzonte — di giorno è celeste, al
        // tramonto arancio — e scende verso lo scafo: l'ultima onda è lo scafo.
        let layers: [(offset: CGFloat, amplitude: CGFloat, wavelength: CGFloat, speed: Double, top: UInt32, bottom: UInt32)] = [
            (0, 4, 190, 0.35, Livery.mix(hullHex, sky.horizon, 0.46), Livery.mix(hullHex, sky.horizon, 0.3)),
            (16, 6, 140, 0.55, Livery.mix(hullHex, sky.horizon, 0.2), Livery.mix(hullHex, sky.horizon, 0.08)),
            (34, 8, 110, 0.8, hullHex, hullHex),
        ]
        for (index, layer) in layers.enumerated() {
            if index == 1 { drawShip(in: &canvas, size: size, horizonY: horizonY, time: time) }
            // Il riflesso va sopra la seconda onda: sotto, ne restava visibile una
            // striscia di pochi punti e non si vedeva.
            if index == 2 {
                drawGlitter(in: &canvas, size: size, horizonY: horizonY, time: time, light: light,
                            avoiding: shipSpan(size: size, time: time))
            }
            let baseY = horizonY + layer.offset
            let phase = time * layer.speed
            var crest = Path()
            var x: CGFloat = 0
            while x <= size.width + 4 {
                let y = baseY + sin(Double(x) / Double(layer.wavelength) * 2 * .pi + phase) * Double(layer.amplitude)
                if x == 0 { crest.move(to: CGPoint(x: x, y: y)) } else { crest.addLine(to: CGPoint(x: x, y: y)) }
                x += 4
            }
            var body = crest
            body.addLine(to: CGPoint(x: size.width + 4, y: size.height))
            body.addLine(to: CGPoint(x: 0, y: size.height))
            body.closeSubpath()
            canvas.fill(body, with: .linearGradient(
                Gradient(colors: [Color(hex: layer.top), Color(hex: layer.bottom)]),
                startPoint: CGPoint(x: 0, y: baseY - layer.amplitude),
                endPoint: CGPoint(x: 0, y: min(size.height, baseY + 40))))
            // La cresta: un filo di luce sulle due onde lontane, che dà spessore al mare.
            if index < 2 {
                canvas.stroke(crest, with: .color(.white.opacity(index == 0 ? 0.16 : 0.1)), lineWidth: 1)
            }
        }
    }

    /// Il riflesso del sole o della luna: trattini che luccicano sull'acqua, sotto
    /// la luce, sempre più larghi verso chi guarda.
    private func drawGlitter(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat,
                             time: TimeInterval, light: Light, avoiding ship: ClosedRange<CGFloat>) {
        guard light.center.y < horizonY else { return }
        let color = light.isSun ? Color(hex: Livery.mix(0xFFFFFF, 0xFFC47A, light.low)) : Color(hex: 0xE8ECF6)
        let strength = light.isSun ? 0.85 : 0.5
        var seed: UInt32 = 1_234_567
        func next() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return CGFloat(seed % 10_000) / 10_000
        }
        let rows = 14
        for i in 0..<rows {
            let t = CGFloat(i) / CGFloat(rows - 1)
            let y = horizonY + 3 + t * 30
            let width = 5 + t * 18 + next() * 8
            let x = light.center.x + (next() - 0.5) * (12 + t * 44)
            let rhythm = 1.2 + Double(next()) * 1.8, phase = Double(next()) * 6.3
            let shimmer = time == 0 ? 0.6 : max(0, sin(time * rhythm + phase))
            let alpha = shimmer * strength * Double(1 - t * 0.55)
            guard alpha > 0.03 else { continue }
            // Sulla fiancata della nave il riflesso non c'è: la nave sta davanti.
            if y < horizonY + 20, ship.overlaps((x - width / 2)...(x + width / 2)) { continue }
            canvas.fill(Path(roundedRect: CGRect(x: x - width / 2, y: y, width: width, height: 1.4), cornerRadius: 0.7),
                        with: .color(color.opacity(alpha)))
        }
    }

    /// La nave, che beccheggia e sale sull'onda. Con Riduci movimento sta ferma,
    /// senza scia.
    private func shipScale(size: CGSize) -> CGFloat { min(0.62, size.width / 620) }

    /// Dove sta la nave, a quest'ora: il centro dello scafo.
    ///
    /// Resta nella scena, con una deriva lenta attorno al centro. Prima la
    /// attraversava da un lato all'altro, e per un terzo del giro era fuori: si
    /// apriva Oggi e la nave non c'era. Che navighi lo dicono la scia, l'onda di
    /// prua e le onde che le scorrono verso poppa, come in una ripresa da una barca
    /// che le va accanto.
    private func shipX(size: CGSize, time: TimeInterval) -> CGFloat {
        let drift = time == 0 ? 0 : CGFloat(sin(time * 0.045)) * size.width * 0.07
        return size.width * 0.42 + drift
    }

    /// Lo spazio che la nave occupa in orizzontale, scia esclusa.
    private func shipSpan(size: CGSize, time: TimeInterval) -> ClosedRange<CGFloat> {
        let x = shipX(size: size, time: time), scale = shipScale(size: size)
        return (x - 90 * scale)...(x + 98 * scale)
    }

    private func drawShip(in canvas: inout GraphicsContext, size: CGSize, horizonY: CGFloat, time: TimeInterval) {
        let scale = shipScale(size: size)
        let x = shipX(size: size, time: time)
        let bob = time == 0 ? 0 : CGFloat(sin(time * 0.9)) * 1.4
        let pitch = time == 0 ? 0 : sin(time * 0.75 + 0.6) * 0.018
        var ship = canvas
        ship.translateBy(x: x, y: horizonY + 11 + bob)
        ship.rotate(by: .radians(pitch))
        ship.scaleBy(x: scale, y: scale)
        CruiseShipDrawing.draw(in: &ship, band: Color(hex: livery.hullHex),
                               funnelTop: Color(hex: livery.signalOnHullHex),
                               lit: SeaSky.sunProgress(hour: hour) == nil,
                               foam: time == 0 ? 0 : 0.55, time: time)
    }
}
