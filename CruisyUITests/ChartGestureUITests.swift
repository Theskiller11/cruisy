import XCTest

/// I gesti sulla carta, fatti davvero: due dita, un bordo, un trascinamento.
///
/// Esiste perché i gesti sono l'unica parte dell'app che i test unitari non vedono e
/// che su questo Mac non si possono provare a mano — non c'è `Simulator.app`, e il
/// pannello del simulatore cade. Il 14 settembre 2026 un pinch per rimpicciolire la
/// carta la **chiudeva**, e l'ha trovato Matteo sul telefono. Le cause erano due, e
/// questi test le hanno separate:
///
/// 1. **la barra delle schede stava sopra la carta**: il dito di sotto del pinch ci
///    finiva sopra e si passava alla scheda Nave. L'albero dell'interfaccia salvato al
///    momento del fallimento mostrava la scheda Nave, non Oggi;
/// 2. **la transizione a zoom dalla card ha un proprio gesto di chiusura a pinch**, e
///    SwiftUI non espone nessuna opzione per spegnerlo. Provato rimettendola con la
///    barra già nascosta: il pinch chiudeva di nuovo la carta.
///
/// Lo swipe dal bordo invece non era mai andato: il trascinamento della carta se lo
/// prendeva. Vedi `BackSwipeEnabler`.
///
/// Qui si verifica **cosa succede allo schermo**, non cosa fa il codice: la carta
/// dev'essere ancora lì, e lo zoom dev'essere cambiato davvero.
final class ChartGestureUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // In mare: la carta si apre attorno alla nave, a 7,5°. È lo stato in cui il
        // pulsante dice «Mostra tutta la rotta», che è il modo di leggere lo zoom
        // senza aggiungere niente all'interfaccia.
        app.launchArguments = ["-sample", "atSea",
                               "-cruisy.hasSeenDisclaimer", "YES",
                               "-cruisy.wantsTracking", "NO",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
    }

    /// Apre la carta dalla card di Oggi e aspetta che sia ferma.
    @discardableResult
    private func openChart() -> XCUIElement {
        let card = app.buttons["Apri la carta"]
        XCTAssertTrue(card.waitForExistence(timeout: 15), "la card della carta non c'è")
        card.tap()
        let chart = app.descendants(matching: .any)["Carta nautica"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "la carta non si è aperta")
        XCTAssertTrue(app.buttons["Mostra tutta la rotta"].waitForExistence(timeout: 5),
                      "la carta non è partita attorno alla nave")
        return chart
    }

    private var isChartOpen: Bool { app.buttons["Indietro"].exists }

    // MARK: Quello che non deve chiudere

    func testTabBarIsHiddenOverTheChart() {
        openChart()
        // La prima volta che il pinch "chiudeva la carta" in realtà cambiava scheda:
        // il dito di sotto finiva sulla barra delle schede, che stava sopra la carta.
        // Il messaggio del test diceva "chiusa" e aveva torto — lo diceva l'albero
        // dell'interfaccia al momento del fallimento, dove c'era la scheda Nave.
        let bar = app.tabBars.firstMatch
        XCTAssertFalse(bar.exists && bar.isHittable,
                       "la barra delle schede è sopra la carta, e un pinch la tocca")
    }

    func testPinchToZoomOutKeepsTheChartOpen() {
        let chart = openChart()

        // Scala sotto 1 = dita che si avvicinano = rimpicciolire.
        chart.pinch(withScale: 0.35, velocity: -1.5)

        XCTAssertFalse(app.navigationBars["Nave"].exists,
                       "il pinch ha toccato la barra delle schede ed è passato alla scheda Nave")
        XCTAssertTrue(app.buttons["Indietro"].waitForExistence(timeout: 3),
                      "dopo il pinch la carta non c'è più")
        // E lo zoom è cambiato davvero: oltre il doppio dell'inquadratura della nave
        // il pulsante smette di proporre la rotta intera e propone di tornare.
        XCTAssertTrue(app.buttons["Torna alla nave"].waitForExistence(timeout: 3),
                      "il pinch non ha rimpicciolito la carta")
    }

    func testDraggingDownPansTheChartInsteadOfClosing() {
        let chart = openChart()

        let from = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let to = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        from.press(forDuration: 0.05, thenDragTo: to)

        XCTAssertTrue(app.buttons["Indietro"].waitForExistence(timeout: 3),
                      "trascinare in giù ha chiuso la carta")
        // La carta si è spostata: la nave non è più al centro.
        XCTAssertTrue(app.buttons["Torna alla nave"].waitForExistence(timeout: 3),
                      "il trascinamento non ha spostato la carta")
    }

    // MARK: Quello che deve chiudere

    func testSwipeFromTheLeftEdgeGoesBack() {
        openChart()

        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: middle)

        XCTAssertTrue(app.buttons["Apri la carta"].waitForExistence(timeout: 5),
                      "lo swipe dal bordo non ha riportato a Oggi")
        XCTAssertFalse(isChartOpen)
    }

    func testBackButtonGoesBack() {
        openChart()
        app.buttons["Indietro"].tap()
        XCTAssertTrue(app.buttons["Apri la carta"].waitForExistence(timeout: 5),
                      "il tasto indietro non ha riportato a Oggi")
    }
}
