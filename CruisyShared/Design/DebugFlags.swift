import Foundation

/// Interruttori da riga di comando per provare percorsi che il simulatore non
/// permette di attivare in modo affidabile.
///
/// `accessibilityReduceTransparency` è di sola lettura e non si inietta: senza un
/// interruttore come questo, il percorso "vetro spento" resterebbe non verificato
/// fino a quando qualcuno non lo trova rotto su un telefono vero.
enum DebugFlags {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    /// `-riduciTrasparenza`
    static let forcesReducedTransparency = arguments.contains("-riduciTrasparenza")
    /// `-aumentaContrasto`
    static let forcesIncreasedContrast = arguments.contains("-aumentaContrasto")
    #else
    static let forcesReducedTransparency = false
    static let forcesIncreasedContrast = false
    #endif
}
