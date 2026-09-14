import Foundation
import CoreGraphics

/// Un riquadro geografico.
public struct GeoBounds: Equatable, Sendable {
    public var minLon, minLat, maxLon, maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon; self.minLat = minLat
        self.maxLon = maxLon; self.maxLat = maxLat
    }

    public init(covering coordinates: [Coordinate]) {
        let lons = coordinates.map(\.longitude), lats = coordinates.map(\.latitude)
        self.init(minLon: lons.min() ?? -180, minLat: lats.min() ?? -85,
                  maxLon: lons.max() ?? 180, maxLat: lats.max() ?? 85)
    }

    public func expanded(by degrees: Double) -> GeoBounds {
        GeoBounds(minLon: minLon - degrees, minLat: minLat - degrees,
                  maxLon: maxLon + degrees, maxLat: maxLat + degrees)
    }

    public func intersects(_ other: GeoBounds) -> Bool {
        !(other.minLon > maxLon || other.maxLon < minLon
          || other.minLat > maxLat || other.maxLat < minLat)
    }
}

/// Proiezione di Mercatore, in coordinate di mondo normalizzate 0…1.
///
/// È la proiezione delle carte nautiche: le rotte a rilevamento costante sono rette,
/// e chi ha visto una carta di bordo riconosce la forma. Il prezzo è che le alte
/// latitudini si gonfiano, e alle crociere caraibiche non importa.
public enum Mercator {
    /// Limite oltre il quale la proiezione diverge.
    public static let latitudeLimit = 85.051_129

    public static func worldX(longitude: Double) -> Double {
        (longitude + 180) / 360
    }

    public static func worldY(latitude: Double) -> Double {
        let clamped = min(max(latitude, -latitudeLimit), latitudeLimit)
        let phi = clamped * .pi / 180
        return (1 - log(tan(phi) + 1 / cos(phi)) / .pi) / 2
    }

    public static func longitude(worldX x: Double) -> Double { x * 360 - 180 }

    public static func latitude(worldY y: Double) -> Double {
        let n = .pi - 2 * .pi * y
        return 180 / .pi * atan(0.5 * (exp(n) - exp(-n)))
    }
}

/// Il legame fra il mondo e i punti dello schermo.
public struct ChartProjection: Equatable, Sendable {
    /// Coordinate di mondo dell'angolo in alto a sinistra.
    public let originX: Double
    public let originY: Double
    /// Quanti punti schermo vale un'unità di mondo.
    public let scale: Double
    public let size: CGSize

    public func point(_ coordinate: Coordinate) -> CGPoint {
        CGPoint(x: (Mercator.worldX(longitude: coordinate.longitude) - originX) * scale,
                y: (Mercator.worldY(latitude: coordinate.latitude) - originY) * scale)
    }

    public func coordinate(at point: CGPoint) -> Coordinate {
        Coordinate(latitude: Mercator.latitude(worldY: Double(point.y) / scale + originY),
                   longitude: Mercator.longitude(worldX: Double(point.x) / scale + originX))
    }

    /// Il riquadro geografico effettivamente visibile: serve a scartare in fretta
    /// le coste che non si vedono.
    public var visibleBounds: GeoBounds {
        let topLeft = coordinate(at: .zero)
        let bottomRight = coordinate(at: CGPoint(x: size.width, y: size.height))
        return GeoBounds(minLon: topLeft.longitude, minLat: bottomRight.latitude,
                         maxLon: bottomRight.longitude, maxLat: topLeft.latitude)
    }

    /// Inquadra un riquadro geografico dentro una misura, con un margine in punti.
    public static func fitting(_ bounds: GeoBounds, in size: CGSize,
                               padding: CGFloat = 0) -> ChartProjection {
        guard size.width > 0, size.height > 0 else {
            return ChartProjection(originX: 0, originY: 0, scale: 1, size: size)
        }
        let x0 = Mercator.worldX(longitude: bounds.minLon)
        let x1 = Mercator.worldX(longitude: bounds.maxLon)
        let y0 = Mercator.worldY(latitude: bounds.maxLat)   // il nord sta in alto
        let y1 = Mercator.worldY(latitude: bounds.minLat)

        let usableWidth = max(1, size.width - padding * 2)
        let usableHeight = max(1, size.height - padding * 2)
        let spanX = max(x1 - x0, 1e-9), spanY = max(y1 - y0, 1e-9)
        let scale = min(Double(usableWidth) / spanX, Double(usableHeight) / spanY)

        // Centratura sull'asse che avanza.
        let originX = x0 - (Double(size.width) / scale - spanX) / 2
        let originY = y0 - (Double(size.height) / scale - spanY) / 2
        return ChartProjection(originX: originX, originY: originY, scale: scale, size: size)
    }

    /// Inquadratura centrata su un punto, larga `spanDegrees` gradi di longitudine.
    public static func centred(on coordinate: Coordinate, spanDegrees: Double,
                               in size: CGSize) -> ChartProjection {
        let half = max(spanDegrees, 0.01) / 2
        return fitting(GeoBounds(minLon: coordinate.longitude - half,
                                 minLat: coordinate.latitude - half,
                                 maxLon: coordinate.longitude + half,
                                 maxLat: coordinate.latitude + half),
                       in: size)
    }
}
