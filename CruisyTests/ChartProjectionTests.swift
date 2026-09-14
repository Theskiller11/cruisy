import Testing
import Foundation
import CoreGraphics
@testable import Cruisy

@Suite("Proiezione della carta")
struct ChartProjectionTests {

    private let size = CGSize(width: 370, height: 178)
    private let puertoPlata = Coordinate(latitude: 19.79, longitude: -70.69)
    private let sanJuan = Coordinate(latitude: 18.47, longitude: -66.11)

    @Test("L'inquadratura centrata mette il punto al centro")
    func centredPutsPointInTheMiddle() {
        // È la correzione del baco per cui il dettaglio di ogni scalo mostrava la
        // carta del porto d'imbarco: usava l'inquadratura "attorno alla nave", che
        // prima della partenza ripiega sul primo scalo. Ora si centra sul punto
        // chiesto, e questo test dice cosa vuol dire "centrato".
        let projection = ChartProjection.centred(on: puertoPlata, spanDegrees: 2.6, in: size)
        let point = projection.point(puertoPlata)
        #expect(abs(point.x - size.width / 2) < 1)
        #expect(abs(point.y - size.height / 2) < 1)
    }

    @Test("Due porti diversi danno due inquadrature diverse")
    func differentPortsGiveDifferentFrames() {
        let a = ChartProjection.centred(on: puertoPlata, spanDegrees: 2.6, in: size)
        let b = ChartProjection.centred(on: sanJuan, spanDegrees: 2.6, in: size)
        #expect(a != b)
        // E ognuna tiene il proprio porto in vista, l'altro fuori o al bordo.
        #expect(a.visibleBounds.minLon < puertoPlata.longitude)
        #expect(a.visibleBounds.maxLon > puertoPlata.longitude)
    }

    @Test("Andata e ritorno fra coordinate e punti")
    func roundTrip() {
        let projection = ChartProjection.centred(on: sanJuan, spanDegrees: 4, in: size)
        let back = projection.coordinate(at: projection.point(sanJuan))
        #expect(abs(back.latitude - sanJuan.latitude) < 0.01)
        #expect(abs(back.longitude - sanJuan.longitude) < 0.01)
    }

    @Test("Il nord sta in alto")
    func northIsUp() {
        let projection = ChartProjection.centred(on: sanJuan, spanDegrees: 6, in: size)
        let north = projection.point(Coordinate(latitude: sanJuan.latitude + 1, longitude: sanJuan.longitude))
        let south = projection.point(Coordinate(latitude: sanJuan.latitude - 1, longitude: sanJuan.longitude))
        #expect(north.y < south.y)
    }

    @Test("Inquadrare una rotta la fa stare tutta dentro")
    func fittingContainsEverything() {
        let route = [sanJuan, puertoPlata, Coordinate(latitude: 25.77, longitude: -80.19)]
        let projection = ChartProjection.fitting(GeoBounds(covering: route), in: size, padding: 20)
        for coordinate in route {
            let point = projection.point(coordinate)
            #expect(point.x >= 0 && point.x <= size.width, "\(point) fuori in orizzontale")
            #expect(point.y >= 0 && point.y <= size.height, "\(point) fuori in verticale")
        }
    }

    @Test("Il riquadro visibile contiene ciò che si vede")
    func visibleBoundsAreCoherent() {
        let projection = ChartProjection.centred(on: sanJuan, spanDegrees: 3, in: size)
        let bounds = projection.visibleBounds
        #expect(bounds.minLat < sanJuan.latitude && bounds.maxLat > sanJuan.latitude)
        #expect(bounds.minLon < sanJuan.longitude && bounds.maxLon > sanJuan.longitude)
        #expect(bounds.intersects(GeoBounds(covering: [sanJuan])))
    }

    @Test("La proiezione regge una misura degenere senza rompersi")
    func degenerateSizeIsSafe() {
        let projection = ChartProjection.centred(on: sanJuan, spanDegrees: 3, in: .zero)
        let point = projection.point(sanJuan)
        #expect(point.x.isFinite && point.y.isFinite)
    }

    @Test("Le coste sono nel bundle e si caricano")
    func coastlineLoads() {
        // Se questo fallisce, la carta è vuota e l'app non lo direbbe.
        #expect(Coastline.shared.rings.count > 500)
        #expect(Coastline.shared.points.count > 20_000)
        // E i Caraibi ci sono davvero.
        let caribbean = GeoBounds(minLon: -82, minLat: 17, maxLon: -63, maxLat: 27)
        #expect(Coastline.shared.rings(intersecting: caribbean).count > 10)
    }
}
