import XCTest

/// Ogni schermata si apre, e l'app resta viva.
///
/// Nata da un crash scoperto il 14 settembre 2026 fotografando le schermate: la
/// schermata di tutti i porti, quella di «Tutti e N» nel Diario, **faceva crashare
/// l'app** appena si apriva. Nessun test la apriva, perché ci si arriva solo con un
/// tocco. Qui ci si arriva con gli argomenti `-open` di `DebugLaunch`, e per ognuna si
/// controlla un elemento che c'è solo lì.
///
/// Serve anche a chi rifà il design: se una schermata smette di aprirsi, o l'app
/// muore aprendola, lo dice questo test prima di chiunque altro.
final class NavigationSmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-cruisy.hasSeenDisclaimer", "YES",
                                           "-cruisy.wantsTracking", "NO",
                                           "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        return app
    }

    /// Apre una schermata, cerca il suo segno, e controlla che l'app non sia morta
    /// nel frattempo: un crash lascia la schermata Home e nessun elemento.
    private func assertOpens(_ arguments: [String], showing element: (XCUIApplication) -> XCUIElement,
                             _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = launch(arguments)
        XCTAssertTrue(element(app).waitForExistence(timeout: 15),
                      "\(what): la schermata non si è aperta", file: file, line: line)
        // Un secondo di margine: il crash dei porti arrivava quando le righe
        // cominciavano a chiedere le foto, non all'apertura.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground,
                       "\(what): l'app non è più in esecuzione", file: file, line: line)
    }

    func testTodayOpens() {
        assertOpens(["-sample", "inPort", "-tab", "oggi"],
                    showing: { $0.buttons["Apri la carta"] }, "Oggi")
    }

    func testChartOpens() {
        assertOpens(["-sample", "atSea", "-open", "carta"],
                    showing: { $0.descendants(matching: .any)["Carta nautica"] }, "Carta")
    }

    func testItineraryOpens() {
        assertOpens(["-sample", "inPort", "-tab", "itinerario"],
                    showing: { $0.navigationBars.firstMatch }, "Itinerario")
    }

    func testPortDetailOpens() {
        assertOpens(["-sample", "inPort", "-open", "scalo"],
                    showing: { $0.staticTexts["Puerto Plata"] }, "Scalo")
    }

    func testShipOpens() {
        assertOpens(["-sample", "inPort", "-tab", "nave"],
                    showing: { $0.navigationBars["Nave"] }, "Nave")
    }

    func testLogbookOpens() {
        assertOpens(["-sample", "inPort", "-tab", "diario"],
                    // La testata è disegnata dall'app, non dalla barra: si cerca per
                    // identificatore, che non cambia con la lingua.
                    showing: { $0.descendants(matching: .any)["diario-testata"] }, "Diario")
    }

    func testAllPortsOpens() {
        assertOpens(["-sample", "inPort", "-open", "porti"],
                    showing: { $0.navigationBars["Porti toccati"] }, "Tutti i porti")
    }

    func testEditorOpens() {
        assertOpens(["-sample", "inPort", "-open", "editor"],
                    showing: { $0.buttons["Salva"] }, "Editor della crociera")
    }

    func testSettingsOpens() {
        assertOpens(["-sample", "inPort", "-open", "impostazioni"],
                    showing: { $0.navigationBars["Impostazioni"] }, "Impostazioni")
    }

    func testOnboardingOpens() {
        assertOpens(["-sample", "inPort", "-open", "onboarding"],
                    showing: { $0.staticTexts["Quanto manca."] }, "Onboarding")
    }
}
