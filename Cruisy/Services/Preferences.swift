import Foundation
import Observation

/// Le preferenze di chi usa l'app, in un posto solo.
///
/// Fino al 14 settembre 2026 stavano dentro `VoyageStore`, insieme alla crociera, al
/// diario e alla traccia: un oggetto che faceva sei cose, e a cui ogni schermata
/// chiedeva tutto. Qui c'è solo ciò che l'utente ha scelto, letto e scritto su
/// `UserDefaults`, senza nessuna logica di viaggio.
///
/// **Legata al thread principale** perché è `@Observable` e la leggono le viste; le
/// scritture sono sincrone su `UserDefaults`, che è già thread-safe.
@MainActor
@Observable
final class Preferences {

    /// L'unità con cui si scrive la velocità.
    var speedUnit: SpeedUnit = .knots {
        didSet { defaults.set(speedUnit.rawValue, forKey: Keys.speedUnit) }
    }

    /// Chi usa l'app ha già letto e accettato l'avviso sull'attendibilità degli orari.
    var hasSeenDisclaimer: Bool = false {
        didSet { defaults.set(hasSeenDisclaimer, forKey: Keys.disclaimer) }
    }

    /// Vuole il countdown sulla schermata di blocco.
    ///
    /// È una preferenza e non un interruttore momentaneo perché la si chiede
    /// nell'onboarding, quando una crociera non c'è ancora e non ci sarebbe niente
    /// da accendere. L'app se la ricorda e accende l'attività da sé quando arriva
    /// il momento — e resta spegnibile in qualunque istante.
    var wantsLiveActivity: Bool = false {
        didSet { defaults.set(wantsLiveActivity, forKey: Keys.liveActivity) }
    }

    /// Vuole che l'app registri la rotta davvero percorsa.
    ///
    /// Costa batteria e costa il permesso di posizione permanente, quindi non è mai
    /// accesa da sé: la si accende una volta e vale per la crociera.
    var wantsTracking: Bool = false {
        didSet { defaults.set(wantsTracking, forKey: Keys.tracking) }
    }

    /// Quale livrea veste l'app: quella di Cruisy o i colori della compagnia.
    ///
    /// Scritta anche nel contenitore condiviso, perché widget e Live Activity girano
    /// in un altro processo e devono vestirsi allo stesso modo.
    var livery: LiveryChoice = .company {
        didSet {
            defaults.set(livery.rawValue, forKey: LiveryChoice.key)
            LiveryChoice.shared?.set(livery.rawValue, forKey: LiveryChoice.key)
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let speedUnit = "cruisy.speedUnit"
        static let disclaimer = "cruisy.hasSeenDisclaimer"
        static let liveActivity = "cruisy.wantsLiveActivity"
        static let tracking = "cruisy.wantsTracking"
    }

    /// - Parameter defaults: dove leggere e scrivere. Anteprime e test passano un
    ///   dominio effimero, così non toccano le scelte vere di nessuno.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Keys.speedUnit), let unit = SpeedUnit(rawValue: raw) {
            speedUnit = unit
        }
        hasSeenDisclaimer = defaults.bool(forKey: Keys.disclaimer)
        wantsLiveActivity = defaults.bool(forKey: Keys.liveActivity)
        wantsTracking = defaults.bool(forKey: Keys.tracking)
        if let raw = defaults.string(forKey: LiveryChoice.key), let choice = LiveryChoice(rawValue: raw) {
            livery = choice
        }
    }

    /// Preferenze che non toccano il disco: anteprime e test.
    static var ephemeral: Preferences {
        let suite = UserDefaults(suiteName: "cruisy.preferences.ephemeral.\(UUID().uuidString)") ?? .standard
        return Preferences(defaults: suite)
    }
}
