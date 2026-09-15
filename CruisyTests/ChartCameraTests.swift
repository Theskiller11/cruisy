import Testing
import Foundation
import CoreGraphics
@testable import Cruisy

/// Il comportamento del gesto sulla carta, provato senza far girare l'interfaccia.
@Suite("Telecamera della carta")
@MainActor
struct ChartCameraTests {

    private let size = CGSize(width: 400, height: 800)
    private let caribbean = Coordinate(latitude: 18.5, longitude: -66.0)

    private func camera(span: Double = 8) -> ChartCamera {
        ChartCamera(center: caribbean, spanDegrees: span)
    }

    @Test("Trascinare sposta la carta nel verso del dito")
    func panFollowsTheFinger() {
        // Trascinando verso destra si scopre quello che sta a ovest.
        let moved = camera().panned(by: CGSize(width: 100, height: 0), in: size)
        #expect(moved.center.longitude < caribbean.longitude)

        // Verso il basso si scopre quello che sta a nord.
        let down = camera().panned(by: CGSize(width: 0, height: 100), in: size)
        #expect(down.center.latitude > caribbean.latitude)
    }

    @Test("Uno scostamento nullo lascia tutto dov'era")
    func zeroPanIsIdentity() {
        let same = camera().panned(by: .zero, in: size)
        #expect(abs(same.center.latitude - caribbean.latitude) < 1e-9)
        #expect(abs(same.center.longitude - caribbean.longitude) < 1e-9)
    }

    @Test("Il punto sotto le dita resta fermo mentre si ingrandisce")
    func zoomKeepsTheAnchorStill() {
        // È la differenza fra un pizzico che si sente giusto e uno che scivola:
        // quello che stavi guardando deve restare dov'era.
        let anchor = CGPoint(x: 320, y: 200)
        let start = camera()
        let before = ChartProjection.centred(on: start.center, spanDegrees: start.spanDegrees, in: size)
        let pinned = before.coordinate(at: anchor)

        let zoomed = start.zoomed(by: 2.5, around: anchor, in: size)
        let after = ChartProjection.centred(on: zoomed.center, spanDegrees: zoomed.spanDegrees, in: size)
        let moved = after.point(pinned)

        #expect(abs(moved.x - anchor.x) < 2, "scivolato di \(moved.x - anchor.x) pt in orizzontale")
        #expect(abs(moved.y - anchor.y) < 2, "scivolato di \(moved.y - anchor.y) pt in verticale")
        #expect(zoomed.spanDegrees < start.spanDegrees)
    }

    @Test("Lo zoom resta dentro i limiti al rilascio")
    func zoomIsClamped() {
        #expect(camera(span: 0.001).clamped().spanDegrees == ChartCamera.minimumSpan)
        #expect(camera(span: 5000).clamped().spanDegrees == ChartCamera.maximumSpan)
    }

    @Test("Oltre il limite la carta resiste invece di bloccarsi")
    func resistanceIsProgressive() {
        // Un limite netto legge come "rotto"; una resistenza che cresce legge come
        // "puoi tirare, ma non c'è altro".
        let past = camera(span: ChartCamera.minimumSpan * 0.5).resisted()
        #expect(past.spanDegrees < ChartCamera.minimumSpan)
        #expect(past.spanDegrees > ChartCamera.minimumSpan * 0.5,
                "la resistenza deve frenare, non lasciar correre")

        // Più si insiste, meno si guadagna.
        let little = ChartCamera.rubberBand(10, dimension: 100)
        let lots = ChartCamera.rubberBand(100, dimension: 100)
        #expect(lots > little)
        #expect(lots < little * 10, "la resistenza deve crescere meno che linearmente")
    }

    @Test("Le longitudini girano attorno al mondo")
    func longitudeWraps() {
        #expect(abs(ChartCamera.wrapLongitude(190) - (-170)) < 1e-9)
        #expect(abs(ChartCamera.wrapLongitude(-190) - 170) < 1e-9)
        #expect(abs(ChartCamera.wrapLongitude(45) - 45) < 1e-9)
    }

    @Test("La latitudine si ferma prima che Mercatore diverga")
    func latitudeIsClamped() {
        let north = ChartCamera(center: Coordinate(latitude: 89, longitude: 0), spanDegrees: 10).clamped()
        #expect(north.center.latitude <= ChartCamera.latitudeLimit)
    }

    @Test("Lo slancio proietta più lontano del punto di rilascio")
    func momentumProjectsForward() {
        // Un colpetto deve lanciare la carta, non fermarla dove è stato lasciato.
        let slow = ChartCamera.project(velocity: 100)
        let fast = ChartCamera.project(velocity: 1000)
        #expect(fast > slow)
        #expect(slow > 0)
        #expect(ChartCamera.project(velocity: 0) == 0)
    }

    @Test("Sa dire quando la nave è uscita dall'inquadratura")
    func knowsWhenTheShipIsOffScreen() {
        let here = camera(span: 4)
        #expect(!here.isFar(from: caribbean))
        #expect(here.isFar(from: Coordinate(latitude: 40, longitude: -70)))
    }

    @Test("Le due carte condividono la stessa inquadratura")
    func camerasAreInterchangeable() {
        // Passando da vettoriale a satellitare si deve restare dove si stava
        // guardando: entrambe partono da questo stesso tipo.
        let camera = ChartCamera(center: caribbean, spanDegrees: 3).clamped()
        let projection = ChartProjection.centred(on: camera.center,
                                                 spanDegrees: camera.spanDegrees, in: size)
        let middle = projection.coordinate(at: CGPoint(x: size.width / 2, y: size.height / 2))
        #expect(abs(middle.latitude - caribbean.latitude) < 0.01)
        #expect(abs(middle.longitude - caribbean.longitude) < 0.01)
    }

    // MARK: Animazione

    @Test("Scavalcare l'antimeridiano prende la via corta")
    func alignmentCrossesTheAntimeridian() {
        // Fiji verso le Samoa: 179°E e 172°W sono a poche ore di navigazione, ma
        // sono 351 gradi di distanza se si scrivono così. Animando fra i due numeri
        // la carta farebbe il giro del mondo al contrario.
        let fiji = ChartCamera(center: Coordinate(latitude: -17.8, longitude: 178.0),
                               spanDegrees: 6)
        let samoa = ChartCamera(center: Coordinate(latitude: -13.8, longitude: -172.0),
                                spanDegrees: 6)
        let aligned = samoa.aligned(to: fiji)

        #expect(abs(aligned.center.longitude - fiji.center.longitude) < 180)
        #expect(aligned.center.longitude == 188)
        // È lo stesso posto, non un altro: riavvolto torna dov'era.
        #expect(ChartCamera.wrapLongitude(aligned.center.longitude) == -172)
    }

    @Test("Fra due punti vicini l'allineamento non tocca niente")
    func alignmentLeavesNearbyCamerasAlone() {
        let a = ChartCamera(center: caribbean, spanDegrees: 8)
        let b = ChartCamera(center: Coordinate(latitude: 25.8, longitude: -80.2), spanDegrees: 8)
        #expect(b.aligned(to: a) == b)
    }

    @Test("I numeri che si animano descrivono la stessa inquadratura")
    func animatableDataRoundTrips() {
        // `SeaChart` anima interpolando tre numeri: Y di Mercatore, longitudine e
        // logaritmo dell'ampiezza. Se il giro d'andata e ritorno non tornasse, la
        // carta si sposterebbe da sola a ogni animazione.
        for camera in [ChartCamera(center: caribbean, spanDegrees: 1.4),
                       ChartCamera(center: Coordinate(latitude: 60.2, longitude: 5.3),
                                   spanDegrees: 60),
                       ChartCamera(center: Coordinate(latitude: -33.9, longitude: 151.2),
                                   spanDegrees: 0.4)] {
            var chart = SeaChart(voyage: SampleVoyage.atSea().voyage, fix: nil,
                                 now: .now, framing: .camera(camera))
            let data = chart.animatableData
            chart.animatableData = data

            guard case .camera(let back) = chart.framing else {
                Issue.record("l'inquadratura non è più una telecamera")
                return
            }
            #expect(abs(back.center.latitude - camera.center.latitude) < 0.0001)
            #expect(abs(back.center.longitude - camera.center.longitude) < 0.0001)
            #expect(abs(back.spanDegrees - camera.spanDegrees) < 0.0001)
        }
    }

    @Test("A metà animazione lo zoom è la media geometrica, non quella aritmetica")
    func zoomInterpolatesInLogSpace() {
        // Da 1° a 100°, a metà strada si deve stare a 10° e non a 50: lo zoom si
        // percepisce in rapporti. In scala lineare la carta si spalancherebbe subito
        // per poi strisciare fino alla fine.
        var stretta = SeaChart(voyage: SampleVoyage.atSea().voyage, fix: nil, now: .now,
                               framing: .camera(ChartCamera(center: caribbean, spanDegrees: 1)))
        let larga = SeaChart(voyage: SampleVoyage.atSea().voyage, fix: nil, now: .now,
                             framing: .camera(ChartCamera(center: caribbean, spanDegrees: 100)))

        let a = stretta.animatableData, b = larga.animatableData
        stretta.animatableData = .init(.init((a.first.first + b.first.first) / 2,
                                             (a.first.second + b.first.second) / 2),
                                       (a.second + b.second) / 2)

        guard case .camera(let mezzo) = stretta.framing else {
            Issue.record("l'inquadratura non è più una telecamera")
            return
        }
        #expect(abs(mezzo.spanDegrees - 10) < 0.01)
    }
}
