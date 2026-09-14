import Foundation
import CoreGraphics

/// Dove sta guardando la carta: un centro e quanto mondo ci sta in larghezza.
///
/// Tipo a sé perché è ciò che il gesto muove. Tenerlo separato dal disegno permette
/// di provarne il comportamento — limiti, resistenza ai bordi, slancio — senza far
/// girare un'interfaccia, che è l'unico modo per sapere davvero come si comporta.
struct ChartCamera: Equatable, Sendable {

    /// Il punto al centro dello schermo.
    var center: Coordinate
    /// Gradi di longitudine coperti dalla larghezza della vista.
    var spanDegrees: Double

    /// Più stretto di così si vedrebbero i singoli moli, e la geometria a 1:50 milioni
    /// non ha quel dettaglio: si ingrandirebbe solo l'imprecisione.
    static let minimumSpan: Double = 0.4
    /// Più largo del mondo intero non ha senso.
    static let maximumSpan: Double = 320

    /// Oltre i poli la proiezione di Mercatore diverge.
    static let latitudeLimit: Double = 78

    init(center: Coordinate, spanDegrees: Double) {
        self.center = center
        self.spanDegrees = spanDegrees
    }

    /// Riporta la telecamera dentro i limiti.
    ///
    /// Si applica al **rilascio**, non durante il gesto: mentre il dito è sullo
    /// schermo la carta deve poter sconfinare un po', perché una resistenza morbida
    /// dice "non c'è altro" mentre un blocco netto dice "si è rotto qualcosa".
    func clamped() -> ChartCamera {
        var camera = self
        camera.spanDegrees = min(max(spanDegrees, Self.minimumSpan), Self.maximumSpan)
        camera.center.latitude = min(max(center.latitude, -Self.latitudeLimit), Self.latitudeLimit)
        camera.center.longitude = Self.wrapLongitude(center.longitude)
        return camera
    }

    /// Le longitudini girano: passando il 180° si riparte da −180 invece di fermarsi.
    static func wrapLongitude(_ value: Double) -> Double {
        var longitude = value
        while longitude > 180 { longitude -= 360 }
        while longitude < -180 { longitude += 360 }
        return longitude
    }

    /// Resistenza progressiva oltre un limite: più si insiste, meno la carta segue.
    ///
    /// La formula è quella dell'elastico di iOS. Un limite duro leggerebbe come
    /// "bloccato"; questa legge come "puoi ancora tirare, ma non c'è altro".
    static func rubberBand(_ overshoot: Double, dimension: Double, constant: Double = 0.55) -> Double {
        guard overshoot != 0, dimension > 0 else { return 0 }
        return (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    /// Applica la resistenza allo zoom quando si esce dai limiti.
    func resisted() -> ChartCamera {
        var camera = self
        if spanDegrees < Self.minimumSpan {
            let overshoot = Self.minimumSpan - spanDegrees
            camera.spanDegrees = Self.minimumSpan - Self.rubberBand(overshoot, dimension: Self.minimumSpan)
        } else if spanDegrees > Self.maximumSpan {
            let overshoot = spanDegrees - Self.maximumSpan
            camera.spanDegrees = Self.maximumSpan + Self.rubberBand(overshoot, dimension: Self.maximumSpan)
        }
        return camera
    }

    /// Dove si fermerebbe un movimento lanciato a questa velocità.
    ///
    /// È la decelerazione dello scorrimento di iOS: si sceglie dove **andrà** il
    /// gesto, non dove è stato lasciato. Un colpetto deve poter lanciare la carta.
    static func project(velocity: Double, decelerationRate: Double = 0.998) -> Double {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// Sposta il centro di uno scostamento in punti schermo.
    func panned(by translation: CGSize, in size: CGSize) -> ChartCamera {
        guard size.width > 0 else { return self }
        let degreesPerPoint = spanDegrees / Double(size.width)
        var camera = self
        camera.center.longitude -= Double(translation.width) * degreesPerPoint
        // La latitudine non è lineare in Mercatore: si passa dalle coordinate di
        // mondo, altrimenti verso i poli il dito e la carta si separano.
        let worldY = Mercator.worldY(latitude: center.latitude)
        let worldPerPoint = (spanDegrees / 360) / Double(size.width)
        camera.center.latitude = Mercator.latitude(
            worldY: worldY - Double(translation.height) * worldPerPoint)
        return camera
    }

    /// Ingrandisce attorno a un punto dello schermo, che resta fermo sotto le dita.
    func zoomed(by factor: Double, around anchor: CGPoint, in size: CGSize) -> ChartCamera {
        guard factor > 0, size.width > 0, size.height > 0 else { return self }

        let before = ChartProjection.centred(on: center, spanDegrees: spanDegrees, in: size)
        let pinned = before.coordinate(at: anchor)

        var camera = self
        camera.spanDegrees = spanDegrees / factor

        // Riporta sotto il dito il punto che c'era prima.
        let after = ChartProjection.centred(on: camera.center, spanDegrees: camera.spanDegrees, in: size)
        let moved = after.point(pinned)
        return camera.panned(by: CGSize(width: anchor.x - moved.x, height: anchor.y - moved.y),
                             in: size)
    }

    /// La stessa inquadratura, con la longitudine scritta nel modo più vicino a un
    /// riferimento.
    ///
    /// 179° e −179° sono lo stesso posto, ma sono due numeri lontanissimi: animando
    /// da uno all'altro la carta farebbe il giro lungo del mondo invece di scavalcare
    /// l'antimeridiano in un dito. Si applica **prima** di animare; durante i gesti
    /// non serve, perché lì la longitudine si muove per differenze piccole.
    func aligned(to reference: ChartCamera) -> ChartCamera {
        var camera = self
        let base = reference.center.longitude
        while camera.center.longitude - base > 180 { camera.center.longitude -= 360 }
        while camera.center.longitude - base < -180 { camera.center.longitude += 360 }
        return camera
    }

    /// Quanto dista, in frazione di inquadratura, da un altro punto: serve a decidere
    /// se mostrare il pulsante "torna alla nave".
    func isFar(from coordinate: Coordinate) -> Bool {
        let dLon = abs(ChartCamera.wrapLongitude(center.longitude - coordinate.longitude))
        let dLat = abs(center.latitude - coordinate.latitude)
        return dLon > spanDegrees * 0.4 || dLat > spanDegrees * 0.4
    }
}
