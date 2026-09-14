import Testing
import Foundation
@testable import Cruisy

/// L'Info.plist **compilato**, non il file sorgente.
///
/// Esiste per un crash arrivato fino al telefono il 14 settembre 2026: la modalità in
/// background era scritta in `INFOPLIST_KEY_UIBackgroundModes`, un'impostazione che
/// Xcode non conosce e ignora in silenzio. Il progetto sembrava a posto, la build era
/// verde, e l'app crashava appena si concedeva la posizione «Sempre». Leggere il file
/// sorgente non l'avrebbe scoperto; leggere il bundle sì.
@Suite("Info.plist compilato")
struct InfoPlistTests {

    private func value(_ key: String) -> Any? {
        Bundle.main.object(forInfoDictionaryKey: key)
    }

    @Test("I test girano dentro l'app, se no questa suite non verifica niente")
    func testsAreHostedInTheApp() {
        #expect(Bundle.main.bundleIdentifier == "it.matteopapini.Cruisy")
    }

    @Test("La posizione in background è dichiarata")
    func backgroundLocationIsDeclared() {
        let modes = value("UIBackgroundModes") as? [String] ?? []
        #expect(modes.contains("location"),
                "senza, CoreLocation fa crashare l'app quando si accende la registrazione")
        #expect(LocationService.declaresBackgroundLocation)
    }

    @Test("Ogni permesso di posizione chiesto ha la sua spiegazione")
    func locationPermissionsAreExplained() {
        // Una richiesta senza la frase di spiegazione non mostra il dialogo: su iOS
        // recenti viene scartata, e l'app resta senza permesso senza sapere perché.
        for key in ["NSLocationWhenInUseUsageDescription",
                    "NSLocationAlwaysAndWhenInUseUsageDescription"] {
            let text = value(key) as? String ?? ""
            #expect(!text.isEmpty, "manca \(key)")
        }
    }

    @Test("Si può chiedere a iOS se Meteo di Apple si apre")
    func weatherSchemeIsQueryable() {
        // Senza questa voce `canOpenURL` risponde sempre di no, e il collegamento a
        // Meteo nei giorni in porto non comparirebbe mai, nemmeno sul telefono.
        let schemes = value("LSApplicationQueriesSchemes") as? [String] ?? []
        #expect(schemes.contains("weather"))
    }
}
