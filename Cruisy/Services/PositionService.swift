import Foundation
import CoreLocation
import Observation

/// Decide qual è la miglior posizione della nave in questo momento.
///
/// L'intuizione che tiene in piedi tutta l'app senza un contratto AIS: **in giorno
/// di mare, chi usa Cruisy è sulla nave**. Non può essere altrove. Quindi il GPS del
/// telefono *è* la posizione della nave — preciso, gratuito, e funzionante in mezzo
/// all'oceano dove non arriva né la rete né l'AIS terrestre.
///
/// In porto la regola si rovescia: si può essere scesi a terra, e allora il telefono
/// dice dove sei **tu**, mentre la nave è ferma in banchina. Da quella differenza
/// nasce il "sei a 3,4 km dalla nave", che è l'informazione che conta davvero mentre
/// il countdown scorre.
@Observable
final class PositionService {

    let location = LocationService()

    /// Oltre questa distanza dal molo si è considerati scesi a terra.
    /// Una nave è lunga qualche centinaio di metri e il GPS in banchina è impreciso,
    /// quindi la soglia è generosa: dire "sei a terra" a chi è a bordo sarebbe
    /// peggio del contrario.
    private let ashoreThreshold: CLLocationDistance = 600

    func requestAccess() { location.requestAccess() }
    func start() { location.start() }
    func stop() { location.stop() }

    var isAuthorised: Bool { location.isAuthorised }
    var isDenied: Bool { location.isDenied }

    // MARK: La rotta percorsa

    func requestAlwaysAccess() { location.requestAlwaysAccess() }
    var canTrackInBackground: Bool { location.canTrackInBackground }
    var isTracking: Bool { location.isTracking }

    /// Accende o spegne la registrazione, e collega dove finiscono i punti.
    ///
    /// Idempotente di proposito: la chiama un `task` che riparte a ogni battito
    /// dell'orologio, e riaccendere qualcosa già acceso deve costare zero.
    func setTracking(_ wanted: Bool, onFix: @escaping (CLLocation) -> Void) {
        if wanted, canTrackInBackground {
            location.onFix = onFix
            guard !location.isTracking else { return }
            location.startTracking()
        } else if location.isTracking {
            location.onFix = nil
            location.stopTracking()
        }
    }

    /// Dove sei tu, se il permesso c'è e il GPS ha agganciato.
    var userFix: CLLocation? { location.lastFix }

    /// Vero quando ci si può fidare del telefono come sensore della nave.
    func isDeviceAboard(_ voyage: Voyage, at now: Date) -> Bool {
        guard let fix = location.lastFix else { return false }
        switch voyage.moment(at: now) {
        case .atSea:
            // In navigazione non esiste "a terra": se il telefono è acceso qui,
            // è a bordo.
            return true
        case .inPort(let call):
            let ship = CLLocation(latitude: call.coordinate.latitude,
                                  longitude: call.coordinate.longitude)
            return fix.distance(from: ship) <= ashoreThreshold
        case .beforeVoyage, .completed, .none:
            return false
        }
    }

    /// La miglior posizione disponibile della nave, con la sua provenienza dichiarata.
    func shipFix(for voyage: Voyage, at now: Date) -> ShipFix? {
        if isDeviceAboard(voyage, at: now), let fix = location.lastFix {
            return ShipFix(
                coordinate: Coordinate(latitude: fix.coordinate.latitude,
                                       longitude: fix.coordinate.longitude),
                timestamp: fix.timestamp,
                course: fix.course >= 0 ? fix.course : nil,
                // CoreLocation dà metri al secondo; in mare si ragiona in nodi.
                speed: fix.speed >= 0 ? fix.speed * 1.943_844 : nil,
                origin: .device)
        }
        return voyage.scheduledFix(at: now)
    }

    /// Quanto sei lontano dalla nave, in metri.
    ///
    /// Nullo quando la domanda non ha senso: se sei a bordo la risposta è zero e non
    /// vale la pena dirla, e senza permesso non c'è risposta da dare.
    func distanceToShip(for voyage: Voyage, at now: Date) -> CLLocationDistance? {
        guard case .inPort(let call) = voyage.moment(at: now),
              let fix = location.lastFix,
              !isDeviceAboard(voyage, at: now)
        else { return nil }

        let ship = CLLocation(latitude: call.coordinate.latitude,
                              longitude: call.coordinate.longitude)
        return fix.distance(from: ship)
    }
}
