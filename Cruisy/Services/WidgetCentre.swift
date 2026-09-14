import Foundation
import WidgetKit

/// Un solo punto da cui si svegliano i widget.
///
/// Serve perché ricaricare le timeline è un'operazione che il sistema può limitare:
/// concentrarla qui rende evidente quante volte la si chiede, invece di spargere
/// `WidgetCenter.shared.reloadAllTimelines()` in giro finché non diventa un tic.
enum WidgetCentre {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
