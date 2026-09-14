import Foundation

#if DEBUG
/// Dove aprire l'app all'avvio, per verificarla senza toccare lo schermo.
///
/// Su questo Mac non c'è `Simulator.app` e il pannello del simulatore cade: `simctl`
/// sa avviare l'app e fotografarla, ma **non sa toccare**. Senza questi argomenti,
/// ogni schermata che non sia la prima si potrebbe verificare solo con un test di
/// interfaccia — che funziona, ma costa minuti a giro. Con questi, uno screenshot.
///
/// Si passano come argomenti di avvio, e `UserDefaults` li legge da sé:
///
///     xcrun simctl launch booted it.matteopapini.Cruisy -sample inPort -tab diario
///     xcrun simctl launch booted it.matteopapini.Cruisy -sample atSea -open carta
///
/// `scripts/screenshots.sh` li usa tutti.
enum DebugLaunch {

    /// La scheda: `oggi`, `itinerario`, `nave`, `diario`.
    static var tab: String? { value("tab") }

    /// Una schermata dentro una scheda: `carta`, `scalo`, `porti`, `editor`,
    /// `importazione`, `impostazioni`, `onboarding`.
    static var open: String? { value("open") }

    /// `-livrea rosso` veste l'app con una livrea del catalogo, per nome (`Livery.id`).
    ///
    /// Esiste perché la nave di prova non è nell'elenco, quindi senza questo non si
    /// vedrebbe mai una livrea ispirata a una compagnia se non con una nave vera.
    static var livery: Livery? {
        guard let id = value("livrea") else { return nil }
        return Livery.all.first { $0.id == id }
    }

    /// La scheda che contiene la schermata richiesta con `-open`, così la si vede
    /// senza doverlo scrivere due volte.
    static var tabForOpen: String? {
        switch open {
        case "carta": "oggi"
        case "porti": "diario"
        case "scalo", "editor", "importazione", "impostazioni": "itinerario"
        default: nil
        }
    }

    private static func value(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)?.lowercased()
    }
}
#endif
