import Foundation
import Network
import Observation

/// Se c'è una rete utilizzabile.
///
/// Serve a una cosa sola: quando qualcuno sceglie la carta satellitare e la
/// connessione non c'è, dirglielo. MapKit non segnala il fallimento delle tessere —
/// lascia un rettangolo vuoto — e un rettangolo vuoto in mezzo all'oceano sembra
/// un guasto dell'app invece di una conseguenza prevedibile di essere in mare.
///
/// Osserva soltanto lo stato del percorso di rete: non manda niente e non contatta
/// nessuno.
@Observable
final class Reachability {
    private(set) var isOnline = true
    /// Vero su rete cellulare o hotspot: scaricare tessere satellitari in roaming
    /// marittimo costa, e vale la pena dirlo.
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "cruisy.reachability")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.isExpensive = path.isExpensive || path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
