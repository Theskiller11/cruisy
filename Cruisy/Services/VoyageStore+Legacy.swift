import SwiftUI

// Ponte temporaneo verso il design vecchio: sparisce con l'ultima vista rifatta.
extension VoyageStore {
    var accent: Color { isInPort ? Palette.ashore : Palette.underway }
    var background: LinearGradient { Palette.background(hour: shipHour, inPort: isInPort) }
}
