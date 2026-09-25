import XCTest

/// L'onboarding si attraversa tutto, coi gesti veri: si strappa il biglietto, si
/// timbrano le regole, si sceglie la nave, e il biglietto finale la porta scritta.
///
/// Serve perché ogni passo ha un gesto suo — un trascinamento, un tocco su una
/// riga, un campo con i suggerimenti — e un gesto che smette di funzionare lascia
/// chi apre l'app per la prima volta fermo al primo schermo.
final class OnboardingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-open", "onboarding",
                               "-cruisy.wantsTracking", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        return app
    }

    func testTheWholeFlowWithGestures() {
        let app = launch()

        // Il biglietto si strappa trascinando lungo la perforazione.
        let stub = app.buttons["Strappa il biglietto per iniziare"]
        XCTAssertTrue(stub.waitForExistence(timeout: 15))
        let from = stub.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let to = stub.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)

        // Le tre regole si timbrano.
        let rules = ["Gli annunci di bordo fanno fede", "Funziona senza rete", "Conta in ora di bordo"]
        for rule in rules {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", rule)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "manca la regola «\(rule)»")
            row.tap()
            XCTAssertEqual(row.value as? String, "Timbrato")
        }
        app.buttons["Avanti"].tap()

        // La Live Activity: si passa oltre.
        XCTAssertTrue(app.staticTexts["Sempre sotto gli occhi"].waitForExistence(timeout: 5))
        app.buttons["Avanti"].tap()

        // La nave: si scrive, si sceglie dai suggerimenti.
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Explora I")
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Explora I,")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertTrue(app.buttons["Cambia"].waitForExistence(timeout: 5))
        app.buttons["Avanti"].tap()

        // Il biglietto finale porta la nave e i timbri.
        XCTAssertTrue(app.staticTexts["Quasi a bordo"].waitForExistence(timeout: 5))
        // «Nave» è anche una scheda, sotto il foglio: si cerca il campo col valore.
        let ship = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND value == %@", "Nave", "Explora I")).firstMatch
        XCTAssertTrue(ship.exists, "il biglietto finale non porta la nave scelta")
        XCTAssertTrue(app.descendants(matching: .any)["Timbri: 3 su 3"].exists)

        // E si può uscire senza itinerario.
        app.buttons["Lo faccio più tardi"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["barra-schede"].waitForExistence(timeout: 5))
    }

    /// Chi usa VoiceOver non trascina: «Inizia» fa la stessa cosa.
    func testStartsWithoutTheGesture() {
        let app = launch()
        let start = app.buttons["Inizia"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        XCTAssertTrue(app.staticTexts["Tocca per timbrare"].waitForExistence(timeout: 5))
    }
}
