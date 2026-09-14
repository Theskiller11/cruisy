import Foundation

/// Lo stato del mare in scala Douglas.
///
/// Una traversata non si giudica dai metri d'onda: si giudica da quanto la senti.
/// La scala Douglas è il modo in cui il mare si descrive a bordo, e ha il pregio di
/// dare a ogni gradino un nome che significa qualcosa anche a chi non naviga.
public enum SeaState: Int, Codable, Sendable, CaseIterable {
    case calmo = 0, quasiCalmo, pocoMosso, mosso, moltoMosso
    case agitato, moltoAgitato, grosso, moltoGrosso, tempestoso

    /// Il gradino corrispondente a un'altezza d'onda significativa, in metri.
    public init(waveHeight metres: Double) {
        switch metres {
        case ..<0.01: self = .calmo
        case ..<0.1: self = .quasiCalmo
        case ..<0.5: self = .pocoMosso
        case ..<1.25: self = .mosso
        case ..<2.5: self = .moltoMosso
        case ..<4: self = .agitato
        case ..<6: self = .moltoAgitato
        case ..<9: self = .grosso
        case ..<14: self = .moltoGrosso
        default: self = .tempestoso
        }
    }

    public var label: String {
        switch self {
        case .calmo: String(localized: "Calmo")
        case .quasiCalmo: String(localized: "Quasi calmo")
        case .pocoMosso: String(localized: "Poco mosso")
        case .mosso: String(localized: "Mosso")
        case .moltoMosso: String(localized: "Molto mosso")
        case .agitato: String(localized: "Agitato")
        case .moltoAgitato: String(localized: "Molto agitato")
        case .grosso: String(localized: "Grosso")
        case .moltoGrosso: String(localized: "Molto grosso")
        case .tempestoso: String(localized: "Tempestoso")
        }
    }

    /// Che cosa vuol dire per chi è a bordo.
    ///
    /// Non è una previsione medica e non promette niente: dice solo quanto è
    /// probabile accorgersi del movimento. Su una nave da crociera con gli
    /// stabilizzatori la soglia è molto più alta che su una barca.
    public var comfort: String {
        switch self {
        case .calmo, .quasiCalmo, .pocoMosso:
            String(localized: "Non lo sentirai")
        case .mosso:
            String(localized: "Movimento appena percettibile")
        case .moltoMosso:
            String(localized: "Beccheggio avvertibile")
        case .agitato:
            String(localized: "Movimento evidente")
        case .moltoAgitato, .grosso:
            String(localized: "Mare impegnativo")
        case .moltoGrosso, .tempestoso:
            String(localized: "Mare molto duro")
        }
    }

    /// Il colore va sempre insieme al nome, mai da solo.
    public var isRough: Bool { rawValue >= SeaState.agitato.rawValue }

    /// Dove si trova la nave rispetto al mare di cui si parla.
    public enum Mooring: Sendable, Equatable {
        /// In navigazione: il moto della nave si sente.
        case underway
        /// In banchina: la nave è legata al molo e il moto non si sente.
        case alongside
        /// All'ancora, e a terra si va col tender: il mare conta, ma per la barca.
        case tender
    }

    /// La riga sotto il nome del mare, secondo dove si è. Nulla quando non c'è
    /// niente di utile da dire.
    ///
    /// Fino al 14 settembre 2026 si mostrava sempre `comfort`, e a nave ormeggiata la
    /// scheda del meteo diceva «Beccheggio avvertibile»: vero in mare aperto, assurdo
    /// in banchina. Col tender invece il mare conta eccome, ma per un'altra ragione.
    public func note(_ mooring: Mooring) -> String? {
        switch mooring {
        case .underway: comfort
        case .alongside: nil
        case .tender: tenderNote
        }
    }

    /// Com'è andare a terra col tender con questo mare.
    ///
    /// «Può essere sospeso» e non «sarà sospeso»: la decisione è del comandante, e
    /// dipende da vento, riparo della rada e scalandrone. L'app segnala il rischio, non
    /// annuncia una decisione che non spetta a lei.
    public var tenderNote: String {
        switch self {
        case .calmo, .quasiCalmo, .pocoMosso:
            String(localized: "Tender tranquillo")
        case .mosso:
            String(localized: "Tender con un po' d'onda")
        default:
            String(localized: "Con questo mare il tender può essere sospeso")
        }
    }
}

/// Le condizioni in un punto e in un'ora.
///
/// Ogni campo è opzionale perché ogni campo può mancare davvero: il modello marino
/// non copre i bacini chiusi molto piccoli, e in porto l'altezza d'onda spesso non
/// c'è. Meglio una scheda con tre valori veri che una con sei di cui tre inventati.
public struct MarineConditions: Codable, Sendable, Equatable {
    /// L'ora a cui si riferiscono i valori.
    public var time: Date
    /// Quando sono stati scaricati. Va mostrato: a bordo la rete va e viene, e un
    /// dato di sei ore fa non è un dato sbagliato — è un dato vecchio, ed è una
    /// differenza che chi guarda deve poter fare da sé.
    public var fetchedAt: Date

    public var waveHeight: Double?
    public var wavePeriod: Double?
    public var seaTemperature: Double?
    public var airTemperature: Double?
    public var windSpeed: Double?
    public var windDirection: Double?
    public var weatherCode: Int?

    public init(time: Date, fetchedAt: Date, waveHeight: Double? = nil, wavePeriod: Double? = nil,
                seaTemperature: Double? = nil, airTemperature: Double? = nil,
                windSpeed: Double? = nil, windDirection: Double? = nil, weatherCode: Int? = nil) {
        self.time = time
        self.fetchedAt = fetchedAt
        self.waveHeight = waveHeight
        self.wavePeriod = wavePeriod
        self.seaTemperature = seaTemperature
        self.airTemperature = airTemperature
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.weatherCode = weatherCode
    }

    public var seaState: SeaState? { waveHeight.map(SeaState.init(waveHeight:)) }

    /// Una scheda senza nessun valore non si mostra.
    public var isEmpty: Bool {
        waveHeight == nil && seaTemperature == nil && airTemperature == nil
            && windSpeed == nil && weatherCode == nil
    }

    public func age(at now: Date) -> TimeInterval { now.timeIntervalSince(fetchedAt) }

    /// Oltre le tre ore il dato si dichiara vecchio. I modelli girano ogni ora o sei;
    /// tre ore è il punto in cui vale la pena dirlo invece di far finta di niente.
    public func isStale(at now: Date) -> Bool { age(at: now) > 3 * 3600 }
}

/// I codici meteo WMO, ridotti a quello che serve dire.
public enum WeatherCode {
    public static func glyph(_ code: Int, isNight: Bool = false) -> String {
        switch code {
        case 0: isNight ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81, 82: "cloud.heavyrain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    public static func label(_ code: Int) -> String {
        switch code {
        case 0: String(localized: "Sereno")
        case 1: String(localized: "Poco nuvoloso")
        case 2: String(localized: "Parzialmente nuvoloso")
        case 3: String(localized: "Coperto")
        case 45, 48: String(localized: "Nebbia")
        case 51, 53, 55: String(localized: "Pioviggine")
        case 56, 57: String(localized: "Pioviggine gelata")
        case 61, 63, 65: String(localized: "Pioggia")
        case 66, 67: String(localized: "Pioggia gelata")
        case 71, 73, 75: String(localized: "Neve")
        case 77: String(localized: "Nevischio")
        case 80, 81, 82: String(localized: "Rovesci")
        case 85, 86: String(localized: "Rovesci di neve")
        case 95: String(localized: "Temporale")
        case 96, 99: String(localized: "Temporale con grandine")
        default: String(localized: "Nuvoloso")
        }
    }
}
