import Foundation
import CoreLocation
import Observation

/// Il minimo indispensabile attorno a CoreLocation.
///
/// Due modi, non uno.
///
/// **Quando in uso** è il modo normale, quello di sempre: la carta live, il "sei a
/// 1,9 km dalla nave". Non chiede niente di invadente e non consuma niente.
///
/// **Sempre**, con gli aggiornamenti in background, si accende **solo** se chi usa
/// l'app lo chiede, per registrare la rotta davvero percorsa. È l'unica strada che
/// funziona in mezzo all'oceano: il risparmio energetico di iOS —
/// `startMonitoringSignificantLocationChanges` — si appoggia alle celle telefoniche,
/// e in mezzo all'Atlantico non ce n'è nessuna, quindi non si sveglierebbe mai.
/// Restare svegli col GPS costa batteria, e per questo è una scelta esplicita che si
/// spegne da sola quando la crociera finisce.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastFix: CLLocation?

    /// Vero quando la registrazione della rotta è accesa adesso.
    private(set) var isTracking = false

    /// Chiamata a ogni posizione buona. La usa `VoyageStore` per allungare la traccia.
    var onFix: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // In mare la nave si sposta di continuo ma lentamente rispetto al GPS:
        // 50 metri di filtro tolgono il rumore senza perdere il movimento.
        manager.distanceFilter = 50
        authorization = manager.authorizationStatus
    }

    var isAuthorised: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// Vero quando l'utente ha rifiutato: serve a mostrare una spiegazione invece di
    /// richiedere il permesso all'infinito.
    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Vero quando il permesso basta a registrare anche col telefono in tasca.
    var canTrackInBackground: Bool { authorization == .authorizedAlways }

    /// Vero quando l'app dichiara la modalità in background per la posizione.
    ///
    /// Non è una formalità: se manca, impostare `allowsBackgroundLocationUpdates`
    /// **non restituisce un errore, fa crashare l'app** con un'asserzione interna di
    /// CoreLocation. Controllarlo qui trasforma un Info.plist sbagliato — com'era il
    /// 14 settembre 2026 — da un crash all'avvio in una registrazione che funziona
    /// solo in primo piano.
    static var declaresBackgroundLocation: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }

    func requestAccess() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Chiede il permesso permanente.
    ///
    /// iOS lo concede **solo dopo** quello "quando in uso", e mostra la richiesta una
    /// volta sola: se si parte da zero si chiede prima quello normale e si torna qui
    /// quando è stato dato.
    func requestAlwaysAccess() {
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func start() {
        guard isAuthorised else { return }
        manager.startUpdatingLocation()
    }

    func stop() {
        // Fermarsi non deve spegnere la registrazione: `stop()` viene chiamata ogni
        // volta che l'app va in secondo piano, ed è **esattamente** il momento in cui
        // la traccia deve continuare.
        guard !isTracking else { return }
        manager.stopUpdatingLocation()
    }

    // MARK: La rotta percorsa

    func startTracking() {
        guard canTrackInBackground else { return }
        isTracking = true
        // Mai senza la dichiarazione nell'Info.plist: vedi `declaresBackgroundLocation`.
        // In quel caso si registra comunque, ma solo finché l'app è aperta.
        guard Self.declaresBackgroundLocation else {
            manager.startUpdatingLocation()
            return
        }
        manager.allowsBackgroundLocationUpdates = true
        // Senza questo iOS mette in pausa gli aggiornamenti quando gli sembra che
        // non ci si stia muovendo — e una nave a velocità costante gli sembra ferma.
        manager.pausesLocationUpdatesAutomatically = false
        // L'indicatore blu è un obbligo, non un difetto: chi registra deve vederlo.
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        // Anche spegnerlo passa dalla stessa asserzione, quindi stessa protezione.
        if Self.declaresBackgroundLocation { manager.allowsBackgroundLocationUpdates = false }
        manager.showsBackgroundLocationIndicator = false
        manager.stopUpdatingLocation()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isTracking, !canTrackInBackground { stopTracking() }
        if isAuthorised { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        // Un fix vecchio o palesemente impreciso è peggio di nessun fix.
        guard newest.horizontalAccuracy >= 0, newest.horizontalAccuracy < 200 else { return }
        lastFix = newest
        onFix?(newest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Il GPS che non aggancia non è un guasto da mostrare: l'app ripiega
        // sugli orari e lo dichiara.
    }
}
