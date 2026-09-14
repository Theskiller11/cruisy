import Foundation
import CoreLocation

/// Quanto chiedere al GPS, secondo l'uso che se ne fa.
///
/// Fino al 14 settembre 2026 la registrazione della rotta usava
/// `kCLLocationAccuracyNearestTenMeters` con filtro a 50 metri anche col telefono
/// in tasca per una giornata intera: la precisione della carta a tutto schermo,
/// spesa per una traccia che scarta comunque tutto ciò che sta sotto un quarto di
/// miglio (`Track.minimumSeparation`, 463 m) o sotto i due minuti.
///
/// La misura è questa: a 20 nodi una nave fa 617 metri al minuto. Con un filtro a
/// 300 metri il sistema ci sveglia al più ogni mezzo minuto, e `Track` ne tiene uno
/// ogni due; con dieci metri di precisione ci svegliava dieci volte di più per punti
/// che finivano scartati. E i cento metri di errore di `HundredMeters` sono un
/// quinto della maglia con cui la traccia stessa si disegna: invisibili.
///
/// Il risparmio vero non è tanto nel GPS in sé — in mezzo al mare non ci sono celle
/// né Wi-Fi da cui il sistema possa ripiegare — quanto nel **lavoro che non si fa**:
/// meno risvegli del processo in background, meno callback, meno scritture. È la
/// scelta che si può documentare qui e misurare sul telefono; la misura vera, in una
/// giornata di mare, la fa Matteo con il telefono in tasca.
struct LocationProfile: Equatable, Sendable {

    let accuracy: CLLocationAccuracy
    let distanceFilter: CLLocationDistance
    let activityType: CLActivityType

    /// In primo piano: la carta e il «sei a 1,9 km dalla nave» vogliono precisione,
    /// e durano quanto la schermata.
    static let foreground = LocationProfile(
        accuracy: kCLLocationAccuracyNearestTenMeters,
        distanceFilter: 50,
        activityType: .other)

    /// La registrazione della rotta col telefono in tasca: grossolana quanto basta.
    ///
    /// `otherNavigation` dice a CoreLocation che ci si muove su un veicolo che non
    /// è un'auto, e gli permette di regolare il campionamento di conseguenza.
    static let recording = LocationProfile(
        accuracy: kCLLocationAccuracyHundredMeters,
        distanceFilter: 300,
        activityType: .otherNavigation)

    /// Il profilo giusto: in primo piano vince la precisione, in tasca il risparmio.
    static func profile(isRecording: Bool, isForeground: Bool) -> LocationProfile {
        if isForeground { return foreground }
        return isRecording ? recording : foreground
    }

    func apply(to manager: CLLocationManager) {
        manager.desiredAccuracy = accuracy
        manager.distanceFilter = distanceFilter
        manager.activityType = activityType
    }
}
