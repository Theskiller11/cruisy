import XCTest

/// I moduli: importazione, editor, impostazioni.
///
/// Gli smoke test dicono che queste schermate si aprono. Qui si controlla che
/// **funzionino**, perché sono le tre che si toccano davvero con le dita e sono anche
/// le tre che hanno già rotto qualcosa: l'editor metteva l'orologio in manuale senza
/// ritorno, le impostazioni mostravano l'interruttore della Live Activity due volte, e
/// l'importazione è il punto in cui un orario sbagliato entra nell'app.
final class FormsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Svuota un campo di testo: cursore in fondo, poi backspace uno alla volta.
    /// Tutti insieme in una `typeText` ne arrivano solo alcuni.
    private func clear(_ field: XCUIElement) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let length = ((field.value as? String) ?? "").count
        for _ in 0..<(length + 2) { field.typeText(XCUIKeyboardKey.delete.rawValue) }
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-cruisy.hasSeenDisclaimer", "YES",
                                           "-cruisy.wantsTracking", "NO",
                                           "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        return app
    }

    /// Commuta un interruttore di un `Form`.
    ///
    /// La riga è essa stessa uno `Switch` e contiene lo `Switch` vero: toccare la riga
    /// prende l'etichetta e non commuta niente. Il tocco va su quello annidato.
    private func toggle(_ row: XCUIElement) {
        let control = row.switches.firstMatch
        (control.exists ? control : row).tap()
    }

    /// L'interruttore «Segui i porti» si spegne e si riaccende, e con lui compare e
    /// sparisce il selettore dello scarto.
    ///
    /// Era il difetto del 14 settembre: il selettore dello scarto metteva l'orologio
    /// in manuale e non c'era più modo di tornare all'automatico.
    func testShipClockGoesManualAndBack() {
        let app = launch(["-sample", "inPort", "-open", "editor"])
        let follow = app.switches["Segui i porti"]
        XCTAssertTrue(follow.waitForExistence(timeout: 15), "l'editor non si è aperto")
        XCTAssertFalse(app.staticTexts["Scarto da UTC"].exists, "lo scarto non va mostrato quando l'orologio segue i porti")

        // Il tocco va sull'interruttore, non al centro della riga: in un `Form` di
        // SwiftUI il centro è l'etichetta e non commuta niente.
        toggle(follow)
        XCTAssertTrue(app.staticTexts["Scarto da UTC"].waitForExistence(timeout: 5),
                      "spento «Segui i porti» deve comparire lo scarto")

        toggle(follow)
        XCTAssertFalse(app.staticTexts["Scarto da UTC"].waitForExistence(timeout: 2),
                      "riacceso «Segui i porti» lo scarto deve sparire: si torna sempre indietro")
    }

    /// Senza nome della nave non si salva: la crociera senza nave non esiste.
    func testEditorRefusesToSaveWithoutAShipName() {
        let app = launch(["-sample", "inPort", "-open", "editor"])
        let name = app.textFields["Nome della nave"]
        XCTAssertTrue(name.waitForExistence(timeout: 15), "l'editor non si è aperto")
        XCTAssertTrue(app.buttons["Salva"].isEnabled, "con la crociera di prova si salva")

        clear(name)
        XCTAssertFalse(app.buttons["Salva"].isEnabled, "senza nome della nave il salvataggio resta chiuso")
    }

    /// La livrea si sceglie, e l'interruttore della Live Activity è **uno solo**.
    func testSettingsHaveLiveryAndOneLiveActivitySwitch() {
        let app = launch(["-sample", "inPort", "-open", "impostazioni"])
        XCTAssertTrue(app.navigationBars["Impostazioni"].waitForExistence(timeout: 15),
                      "le impostazioni non si sono aperte")
        XCTAssertTrue(app.buttons["Livrea"].exists || app.staticTexts["Livrea"].exists,
                      "manca la scelta della livrea")
        XCTAssertEqual(app.switches.matching(identifier: "Countdown sulla schermata di blocco").count, 1,
                       "l'interruttore della Live Activity deve comparire una volta sola")
    }

    /// L'importazione porta al riesame, e il riesame non si conferma da solo: la
    /// conferma è un tocco esplicito su orari che l'utente ha appena visto.
    func testImportReachesReview() {
        let app = launch(["-sample", "inPort", "-open", "importazione", "-importDemo", "-importLeggi"])
        XCTAssertTrue(app.navigationBars["Controlla"].waitForExistence(timeout: 30),
                      "il riesame non si è aperto")
        XCTAssertTrue(app.staticTexts["Nave"].exists, "il riesame deve mostrare la nave letta")
        XCTAssertTrue(app.switches["Segui i porti"].exists, "il riesame deve avere l'ora di bordo")
        XCTAssertTrue(app.buttons["Conferma e salva"].exists || app.buttons["Sistema le righe segnate"].exists,
                      "manca il pulsante di conferma")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Nel riesame gli orari si correggono sul posto, senza aprire altro.
    func testImportReviewLetsYouFixATime() {
        let app = launch(["-sample", "inPort", "-open", "importazione", "-importDemo", "-importLeggi"])
        XCTAssertTrue(app.navigationBars["Controlla"].waitForExistence(timeout: 30),
                      "il riesame non si è aperto")
        let arrivals = app.textFields.matching(identifier: "orario-arrivo")
        XCTAssertGreaterThan(arrivals.count, 0, "gli orari di arrivo devono essere modificabili")

        let first = arrivals.element(boundBy: 0)
        // Tre tocchi selezionano tutta la riga: i backspace da soli non bastano,
        // perché il cursore cade in mezzo all'orario e quello che resta a destra
        // («00») sopravvive, e l'orario nuovo gli si incolla davanti.
        first.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        first.typeText("10:15")
        app.navigationBars["Controlla"].tap()   // toglie il fuoco: è lì che l'orario si legge
        XCTAssertEqual(first.value as? String, "10:15", "l'orario corretto deve restare")
    }
}
