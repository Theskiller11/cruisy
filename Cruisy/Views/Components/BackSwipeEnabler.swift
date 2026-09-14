import SwiftUI
import UIKit

/// Rimette in funzione lo swipe di sistema dal bordo sinistro sopra una vista che ha
/// gesti suoi a tutto schermo.
///
/// **Il problema.** La carta si trascina con un gesto che parte al primo contatto, e
/// deve farlo: la carta sta incollata al dito da subito. Ma quel gesto si prendeva
/// anche i tocchi che partono dal bordo, e lo swipe per tornare indietro non arrivava
/// mai. L'ha scoperto un test di interfaccia il 14 settembre 2026: lo swipe dal bordo
/// **spostava la carta**.
///
/// **Perché non basta una striscia trasparente sul bordo.** Era il primo tentativo, e
/// non funziona: in SwiftUI una vista senza gesti propri non ferma i gesti delle viste
/// che le stanno sotto. Il test l'ha smentito al primo giro.
///
/// **La soluzione.** Il gesto di sistema è un `UIScreenEdgePanGestureRecognizer`
/// del controller di navigazione. Qui gli si dà un delegato che dice a **tutti gli
/// altri gesti di aspettare che lui fallisca**. Sembra drastico, e non lo è: un gesto
/// dal bordo fallisce all'istante se il tocco non parte dal bordo, quindi la carta non
/// sente nessun ritardo — aspetta solo quando il dito parte davvero da lì. E si ottiene
/// lo swipe vero di iOS, che segue il dito e lascia vedere Oggi sotto, invece di
/// un'imitazione che scatta.
///
/// Serve anche per un secondo motivo: la carta nasconde la barra di navigazione, e
/// senza un delegato suo il gesto di sistema può rifiutarsi di partire.
struct BackSwipeEnabler: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {

        private weak var recognizer: UIGestureRecognizer?
        /// Il delegato di prima, da rimettere uscendo: il controller di navigazione
        /// lo usa per tutte le altre schermate, che non devono accorgersi di niente.
        private weak var previousDelegate: UIGestureRecognizerDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            if pop.delegate !== self { previousDelegate = pop.delegate }
            recognizer = pop
            pop.delegate = self
            pop.isEnabled = true
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // Si rimette a posto anche a swipe **iniziato**: il gesto è già partito e
            // non ha più bisogno del delegato. Se l'utente ci ripensa e torna sulla
            // carta, `viewDidAppear` lo riprende.
            if recognizer?.delegate === self { recognizer?.delegate = previousDelegate }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Mai alla radice: uno swipe indietro senza niente dietro blocca la pila di
            // navigazione, ed è un difetto noto di UIKit.
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
