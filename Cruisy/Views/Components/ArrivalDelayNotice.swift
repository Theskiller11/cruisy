import SwiftUI

/// L'avviso che, all'andatura di queste ore, si arriverà in ritardo.
///
/// Compare solo in mare, solo con la rotta registrata, e solo quando `ArrivalEstimate`
/// dice che il ritardo supera l'ora. Il testo dice **due** cose, e la seconda conta
/// quanto la prima: gli orari che valgono restano quelli annunciati a bordo. L'avviso
/// serve a prepararsi, non a sostituire la voce del comandante.
struct ArrivalDelayNotice: View {
    let estimate: ArrivalEstimate
    let port: PortCall
    let clock: ShipClock

    var body: some View {
        StaleDataNotice(message: "All'andatura di queste ore arriverete a \(port.name) verso le \(clock.time(estimate.expected)), \(Format.duration(estimate.delay)) dopo l'orario pubblicato. Gli orari che contano restano quelli annunciati a bordo.")
    }
}
