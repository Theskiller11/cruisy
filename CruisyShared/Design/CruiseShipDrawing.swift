import SwiftUI

/// La nave da crociera di profilo, disegnata in un `Canvas`: la stessa nella scena
/// del giorno di mare e in quella dell'onboarding.
///
/// Prima erano due disegni diversi, e quello della scena era una scatola grigia
/// con un fumaiolo: a sei punti al secondo sotto il biglietto, la cosa che si
/// guardava di più era anche la più povera. Questa ha le parti che fanno una nave
/// da crociera a colpo d'occhio: la prua slanciata, i ponti a gradoni con le fasce
/// dei balconi, le scialuppe arancio lungo il fianco, il fumaiolo a poppa, il radar.
///
/// **Nessun marchio.** Scafo e ponti bianchi; la fascia sulla linea di
/// galleggiamento e quella del fumaiolo nel colore della livrea, che è una palette
/// ispirata e non un logo. Le scialuppe nell'arancio delle scialuppe vere.
///
/// Coordinate: la linea di galleggiamento sta a y = 0, la prua verso destra; lo
/// scafo va da x = -88 a x = 96 a scala 1. Chi disegna trasla, ruota e scala il
/// contesto prima di chiamare `draw`.
public enum CruiseShipDrawing {

    /// La lunghezza del disegno a scala 1, per chi deve impaginarlo.
    public static let length: CGFloat = 184

    /// - Parameters:
    ///   - band: la fascia sullo scafo e sul fumaiolo, nel colore della livrea.
    ///   - funnelTop: la cima del fumaiolo, nel segnale della livrea.
    ///   - lit: di notte le finestre si accendono e la luce di via lampeggia.
    ///   - foam: da 0 a 1, quanto corre: l'onda di prua e la scia.
    ///   - time: per far tremare la scia e lampeggiare la luce; 0 li ferma.
    public static func draw(in canvas: inout GraphicsContext, band: Color, funnelTop: Color,
                            lit: Bool, foam: CGFloat, time: TimeInterval) {
        let white = Color(hex: 0xF6F9FC)
        let shade = Color(hex: 0xEEF3F8)
        let glass = lit ? Color(hex: 0xFFD27A) : Color(hex: 0x16304F)

        // L'ombra sull'acqua: attacca la nave al mare invece di lasciarla galleggiare sopra.
        canvas.fill(Path(ellipseIn: CGRect(x: -90, y: 8.5, width: 184, height: 9)),
                    with: .color(.black.opacity(0.18)))

        drawFoam(in: &canvas, foam: foam, time: time)

        // Lo scafo: la cimosa sale verso la prua, il dritto di prua è slanciato, la
        // poppa arrotondata.
        var hull = Path()
        hull.move(to: CGPoint(x: -88, y: -6))
        hull.addLine(to: CGPoint(x: 78, y: -12))
        hull.addCurve(to: CGPoint(x: 95, y: -3), control1: CGPoint(x: 88, y: -12), control2: CGPoint(x: 93, y: -7))
        hull.addLine(to: CGPoint(x: 86, y: 10))
        hull.addLine(to: CGPoint(x: -80, y: 10))
        hull.addCurve(to: CGPoint(x: -88, y: -6), control1: CGPoint(x: -86, y: 8), control2: CGPoint(x: -90, y: 1))
        hull.closeSubpath()
        canvas.fill(hull, with: .color(white))

        var onHull = canvas
        onHull.clip(to: hull)
        onHull.fill(Path(CGRect(x: -95, y: 3.5, width: 200, height: 10)), with: .color(band))
        onHull.fill(Path(CGRect(x: -95, y: -12, width: 200, height: 4)), with: .color(Color(hex: 0xDDE6EF).opacity(0.6)))
        var stripe = Path()
        stripe.move(to: CGPoint(x: -84, y: -2))
        stripe.addLine(to: CGPoint(x: 86, y: -8))
        onHull.stroke(stripe, with: .color(band), lineWidth: 1.3)

        // I ponti, a gradoni: ognuno più corto verso poppa, con la fronte inclinata.
        let decks: [[CGPoint]] = [
            [CGPoint(x: -80, y: -5), CGPoint(x: -80, y: -19), CGPoint(x: 64, y: -21), CGPoint(x: 73, y: -11.5)],
            [CGPoint(x: -72, y: -19), CGPoint(x: -72, y: -29), CGPoint(x: 54, y: -31), CGPoint(x: 62, y: -21)],
            [CGPoint(x: -60, y: -29), CGPoint(x: -60, y: -38), CGPoint(x: 42, y: -39.5), CGPoint(x: 50, y: -31)],
            [CGPoint(x: -8, y: -38.5), CGPoint(x: -8, y: -45), CGPoint(x: 34, y: -46), CGPoint(x: 40, y: -39.5)],
        ]
        for (index, corners) in decks.enumerated() {
            var deck = Path()
            deck.addLines(corners)
            deck.closeSubpath()
            canvas.fill(deck, with: .color(index.isMultiple(of: 2) ? white : shade))
            var edge = Path()
            edge.move(to: corners[0])
            edge.addLine(to: corners[3])
            canvas.stroke(edge, with: .color(Color(hex: 0xC3D0DC)), lineWidth: 0.7)
        }

        // Le fasce dei balconi, coi divisori: sono loro a dire «nave da crociera».
        let bands: [(y: CGFloat, height: CGFloat, from: CGFloat, to: CGFloat)] = [
            (-16, 3.2, -76, 62), (-10.5, 2.6, -77, 66), (-26.5, 3, -68, 52), (-35.5, 2.8, -56, 40),
        ]
        var dividers = Path()
        for band in bands {
            canvas.fill(Path(CGRect(x: band.from, y: band.y, width: band.to - band.from, height: band.height)),
                        with: .color(glass.opacity(lit ? 0.95 : 0.8)))
            var x = band.from + 4
            while x < band.to {
                dividers.move(to: CGPoint(x: x, y: band.y))
                dividers.addLine(to: CGPoint(x: x, y: band.y + band.height))
                x += 4.5
            }
        }
        canvas.stroke(dividers, with: .color(white), lineWidth: 0.7)

        // La plancia: una fascia di vetro scuro, accesa di notte.
        var bridge = Path()
        bridge.addLines([CGPoint(x: -4, y: -44), CGPoint(x: 33, y: -44.8), CGPoint(x: 37, y: -41), CGPoint(x: -4, y: -41)])
        bridge.closeSubpath()
        canvas.fill(bridge, with: .color(lit ? glass : Color(hex: 0x0B1E36)))

        // Le scialuppe lungo il fianco.
        var boats = Path()
        var x: CGFloat = -58
        while x < 40 {
            boats.addRoundedRect(in: CGRect(x: x, y: -21.5, width: 9, height: 3.6), cornerSize: CGSize(width: 1.8, height: 1.8))
            x += 12
        }
        canvas.fill(boats, with: .color(Color(hex: 0xF26A1B)))

        // Il fumaiolo a poppa, inclinato all'indietro: bianco, con la fascia della
        // livrea e la cima nel segnale. Pieno nel colore della livrea spariva sui
        // fondi scuri, e restava a mezz'aria solo la cima.
        var funnel = Path()
        funnel.addLines([CGPoint(x: -54, y: -38), CGPoint(x: -34, y: -38), CGPoint(x: -38, y: -58), CGPoint(x: -56, y: -58)])
        funnel.closeSubpath()
        canvas.fill(funnel, with: .color(white))
        var marks = canvas
        marks.clip(to: funnel)
        marks.fill(Path(CGRect(x: -58, y: -51, width: 26, height: 5.5)), with: .color(band))
        marks.fill(Path(CGRect(x: -58, y: -58, width: 26, height: 3.5)), with: .color(funnelTop))

        // L'albero con la cupola del radar.
        var mast = Path()
        mast.move(to: CGPoint(x: 20, y: -46))
        mast.addLine(to: CGPoint(x: 19, y: -57))
        canvas.stroke(mast, with: .color(white), lineWidth: 1.4)
        canvas.fill(Path(ellipseIn: CGRect(x: 15.8, y: -62.7, width: 6.4, height: 6.4)), with: .color(white))

        // Di notte, la luce di via verde a prua.
        if lit {
            let blink = time == 0 ? 1 : 0.55 + 0.45 * sin(time * 3)
            canvas.fill(Path(ellipseIn: CGRect(x: 92.6, y: -6.4, width: 2.8, height: 2.8)),
                        with: .color(Color(hex: 0x7CF09A).opacity(blink)))
        }
    }

    /// L'onda di prua e la scia: bianche, tanto più lunghe quanto più la nave corre.
    private static func drawFoam(in canvas: inout GraphicsContext, foam: CGFloat, time: TimeInterval) {
        guard foam > 0.02 else { return }
        for row in 0..<3 {
            let y = 4 + CGFloat(row) * 3.5
            let length = (70 + CGFloat(row) * 30) * foam
            let wobble = CGFloat(sin(time * 5 + Double(row) * 1.3)) * 2.5
            var streak = Path()
            streak.addRoundedRect(in: CGRect(x: -88 - length + wobble, y: y, width: length, height: 1.6),
                                  cornerSize: CGSize(width: 0.8, height: 0.8))
            canvas.fill(streak, with: .color(.white.opacity(Double(0.6 * foam) / Double(row + 1))))
        }
        var bow = Path()
        bow.move(to: CGPoint(x: 86, y: 3))
        bow.addQuadCurve(to: CGPoint(x: 86 + 22 * foam, y: 6), control: CGPoint(x: 100, y: 3 - 5 * foam))
        bow.addQuadCurve(to: CGPoint(x: 86, y: 9), control: CGPoint(x: 96, y: 7))
        bow.closeSubpath()
        canvas.fill(bow, with: .color(.white.opacity(Double(0.85 * foam))))
    }
}
