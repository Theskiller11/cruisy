import Foundation

/// Da dove viene un orario. Sempre visibile accanto al numero.
///
/// È l'idea migliore del brief, che però la teneva confinata in un caso limite di un
/// widget ("countdown da orario pubblicato, non da AIS"). Qui è un campo obbligatorio:
/// non si può costruire un countdown senza dichiarare da dove arriva. Un'app che può
/// farti perdere la nave deve dire sempre quanto si sta fidando di sé stessa.
public enum CountdownOrigin: String, Codable, Sendable, CaseIterable {
    /// L'orario pubblicato dalla compagnia, inserito da chi usa l'app.
    case publishedSchedule
    /// Corretto a mano dopo un annuncio di bordo. Ha la precedenza su tutto.
    case userEdited
    /// Stimato dall'app da posizione e velocità. Indicativo.
    case estimated

    /// Etichetta breve da mettere accanto al countdown.
    public var label: String {
        switch self {
        case .publishedSchedule: String(localized: "orario pubblicato", comment: "Provenienza del countdown")
        case .userEdited: String(localized: "corretto da te", comment: "Provenienza del countdown")
        case .estimated: String(localized: "stima", comment: "Provenienza del countdown")
        }
    }

    /// La provenienza come valore di un campo del biglietto: «Pubblicato».
    public var fieldValue: String {
        switch self {
        case .publishedSchedule: String(localized: "Pubblicato", comment: "Campo Orario del biglietto")
        case .userEdited: String(localized: "Corretto da te", comment: "Campo Orario del biglietto")
        case .estimated: String(localized: "Stimato", comment: "Campo Orario del biglietto")
        }
    }

    /// Quanto ci si può appoggiare a questo orario. Governa il glifo mostrato, così
    /// la provenienza non è affidata al solo colore.
    public var isAuthoritative: Bool {
        switch self {
        case .publishedSchedule, .userEdited: true
        case .estimated: false
        }
    }
}

/// Un conto alla rovescia verso un istante preciso.
///
/// Porta con sé anche `start`, cioè da quando l'attesa è cominciata. Serve perché
/// l'anello di progresso deve misurare **lo stesso evento** del numero che abbraccia:
/// nel brief l'anello segnava la sosta in porto (09:00→18:00) mentre il numero contava
/// verso l'all aboard delle 17:30, due cose diverse attaccate l'una all'altra.
///
/// Nessun contatore, nessun tick: solo due istanti. È l'unico modo perché il conto
/// resti giusto dopo un periodo in background, e l'unico che widget e Live Activity
/// possano rendere, visto che lì non si può far girare un timer.
public struct Countdown: Equatable, Sendable, Codable {

    /// Da quando l'attesa è cominciata: l'attracco per un all aboard, la partenza dal
    /// porto precedente per un arrivo.
    public let start: Date
    /// L'istante verso cui si conta.
    public let target: Date
    public let origin: CountdownOrigin

    public init(start: Date, target: Date, origin: CountdownOrigin) {
        // Un intervallo rovesciato produrrebbe progressi negativi in giro per l'app.
        self.start = min(start, target)
        self.target = target
        self.origin = origin
    }

    /// L'intervallo da passare a `Text(timerInterval:)`, che il sistema aggiorna da sé.
    public var range: ClosedRange<Date> { start...target }

    /// Secondi mancanti, mai negativi.
    public func remaining(at now: Date) -> TimeInterval {
        max(0, target.timeIntervalSince(now))
    }

    /// Vero quando l'istante è passato.
    public func hasElapsed(at now: Date) -> Bool { now >= target }

    /// Quota di attesa già trascorsa, da 0 a 1. È ciò che riempie l'anello.
    public func progress(at now: Date) -> Double {
        let total = target.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    /// Scomposizione in ore, minuti e secondi per la resa a cifre separate.
    public func components(at now: Date) -> (hours: Int, minutes: Int, seconds: Int) {
        let total = Int(remaining(at: now).rounded(.down))
        return (total / 3600, (total % 3600) / 60, total % 60)
    }

    /// "2:58:04" oppure "58:04" sotto l'ora. Cifre a larghezza fissa in resa.
    ///
    /// Con `alwaysHours` le ore ci sono sempre: «0:19:55». Sul biglietto, accanto a
    /// un'ora stampata come «17:30», un «19:55» si leggerebbe come un altro orario
    /// del giorno e non come diciannove minuti — l'ha notato Matteo al primo giro.
    public func formatted(at now: Date, alwaysHours: Bool = false) -> String {
        let c = components(at: now)
        return c.hours > 0 || alwaysHours
            ? String(format: "%d:%02d:%02d", c.hours, c.minutes, c.seconds)
            : String(format: "%d:%02d", c.minutes, c.seconds)
    }

    /// Vero quando manca poco e la cosa va messa in evidenza.
    public func isImminent(at now: Date, within: TimeInterval = 3600) -> Bool {
        let left = remaining(at: now)
        return left > 0 && left <= within
    }
}
