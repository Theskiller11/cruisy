import Testing
import SwiftUI
@testable import Cruisy

/// La forma del biglietto: gli incavi sono buchi, e fuori dal biglietto non c'è niente.
///
/// Nasce da un difetto visto da Matteo il 15 settembre 2026: accanto a ogni incavo
/// sporgeva una mezzaluna bianca. I cerchi erano aggiunti al tracciato e riempiti con la
/// regola pari/dispari, che buca la metà interna ma dipinge quella esterna.
@Suite("Forma del biglietto")
struct TicketShapeTests {
    let rect = CGRect(x: 0, y: 0, width: 300, height: 400)
    let shape = TicketShape(cornerRadius: 18, perforationY: 250, notchRadius: 11)

    @Test("fuori dal bordo, all'altezza della perforazione, la carta non sporge")
    func nothingOutsideTheNotch() {
        let path = shape.path(in: rect)
        #expect(!path.contains(CGPoint(x: -5, y: 250)))
        #expect(!path.contains(CGPoint(x: 305, y: 250)))
        #expect(!path.contains(CGPoint(x: -5, y: 250), eoFill: true))
        #expect(!path.contains(CGPoint(x: 305, y: 250), eoFill: true))
    }

    @Test("dentro l'incavo c'è un buco")
    func theNotchIsAHole() {
        let path = shape.path(in: rect)
        #expect(!path.contains(CGPoint(x: 5, y: 250)))
        #expect(!path.contains(CGPoint(x: 295, y: 250)))
    }

    @Test("il resto del biglietto è carta")
    func theRestIsPaper() {
        let path = shape.path(in: rect)
        #expect(path.contains(CGPoint(x: 150, y: 250)))
        #expect(path.contains(CGPoint(x: 5, y: 100)))
        #expect(path.contains(CGPoint(x: 295, y: 350)))
    }

    @Test("il riquadro della forma non va oltre il biglietto")
    func boundsStayInside() {
        let bounds = shape.path(in: rect).boundingRect
        #expect(bounds.minX >= rect.minX - 0.5)
        #expect(bounds.maxX <= rect.maxX + 0.5)
    }
}
