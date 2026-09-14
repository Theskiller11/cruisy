import SwiftUI

/// L'avviso che stanotte la nave sposta l'orologio.
///
/// Non è un vezzo: **è uno dei modi più comuni di perdere la nave.** L'orologio gira
/// alle 02:00, il telefono no — il telefono segue il fuso della rete, o non cambia
/// affatto in mezzo all'oceano — e la mattina dopo chi si è fidato del telefono ha
/// un'ora in meno di quella che crede. Cruisy esiste per questo, quindi dirlo prima
/// vale più di qualunque altra cosa possa stare in quello spazio.
///
/// La sveglia del telefono, per inciso, **non** si sposta da sola: chi la usa per
/// scendere a terra la mattina dopo va avvisato adesso.
struct ClockChangeNotice: View {
    let clock: ShipClock
    let now: Date

    /// Da quanto prima si avvisa.
    ///
    /// Venti ore: abbastanza da prendere tutta la sera prima — che è quando uno
    /// pianifica la giornata dopo e punta la sveglia — e non tanto da comparire per
    /// giorni. Un avviso che sta lì da tre giorni non è un avviso, è arredamento.
    private static let leadTime: TimeInterval = 20 * 3600

    private var imminent: ShipClock.Change? {
        guard let next = clock.nextChange(after: now),
              next.at.timeIntervalSince(now) <= Self.leadTime,
              clock.shift(at: next) != 0
        else { return nil }
        return next
    }

    var body: some View {
        if let change = imminent {
            let shift = clock.shift(at: change)
            let hours = abs(shift) / 3600
            // L'ora del cambio si scrive **con l'orologio di prima**, che è quello
            // che ha al polso chi sta andando a dormire.
            let when = clock.timeBeforeChange(change)

            HullNotice(shift > 0
                ? "Stanotte alle \(when) l'orologio di bordo va avanti di \(hours == 1 ? String(localized: "un'ora") : String(localized: "\(hours) ore")). Dormirai di meno: la sveglia del telefono non si sposta da sola."
                : "Stanotte alle \(when) l'orologio di bordo torna indietro di \(hours == 1 ? String(localized: "un'ora") : String(localized: "\(hours) ore")). Guadagni un'ora: gli orari di domani non cambiano, cambia l'orologio.",
                glyph: "clock.arrow.trianglehead.2.counterclockwise.rotate.90")
        }
    }
}
