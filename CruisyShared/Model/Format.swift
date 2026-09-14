import Foundation

/// Numeri e date, scritti come li scrive la lingua di chi legge.
///
/// Passa da `NumberFormatter` e non da `String(format:)`: in italiano il separatore
/// decimale è la virgola, e cablarlo a mano vorrebbe dire sbagliarlo in ogni altra
/// lingua. Le istanze sono statiche perché costruirne una è caro e queste finiscono
/// dentro viste che si ridisegnano spesso.
public enum Format {

    private static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        return f
    }()

    private static let whole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        // Esplicito: le miglia di una vita di crociere arrivano a cinque cifre, e
        // "25000 mn" si legge peggio di "25.000 mn".
        f.usesGroupingSeparator = true
        return f
    }()

    private static func one(_ value: Double) -> String {
        decimal.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func integer(_ value: Double) -> String {
        whole.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
    }

    /// "420 m" sotto il chilometro, "3,4 km" sopra.
    public static func distance(metres: Double) -> String {
        metres < 1_000 ? "\(integer(metres)) m" : "\(one(metres / 1_000)) km"
    }

    /// "18,4 kt" oppure "34,1 km/h", secondo la preferenza.
    public static func speed(knots: Double, unit: SpeedUnit) -> String {
        "\(one(unit.value(fromKnots: knots))) \(unit.suffix)"
    }

    /// "218 mn". Le miglia nautiche si dicono intere.
    ///
    /// L'abbreviazione cambia con la lingua: `mn` in italiano, `NM` in inglese.
    /// Scritta a mano nel codice, in inglese resterebbe sbagliata.
    public static func nauticalMiles(_ value: Double) -> String {
        "\(integer(value)) \(String(localized: "mn", comment: "Abbreviazione di miglia nautiche"))"
    }

    /// "287°".
    public static func bearing(_ degrees: Double) -> String {
        "\(integer(degrees))°"
    }

    /// "287° · O/NO", che è come si legge una rotta.
    public static func course(_ degrees: Double) -> String {
        "\(bearing(degrees)) \(Geo.compassPoint(degrees))"
    }

    /// "63.621 GT" per la stazza lorda.
    public static func tonnage(_ value: Double) -> String {
        "\(integer(value)) GT"
    }

    /// "1,2 m" per l'altezza dell'onda.
    public static func metres(_ value: Double) -> String { "\(one(value)) m" }

    /// "31°" per la temperatura.
    public static func temperature(_ celsius: Double) -> String { "\(integer(celsius))°" }

    /// Un grado in gradi e primi, come su una carta nautica.
    private static func sexagesimal(_ value: Double, positive: String, negative: String) -> String {
        let magnitude = abs(value)
        var degrees = Int(magnitude)
        var minutes = Int(((magnitude - Double(degrees)) * 60).rounded())
        // 60 primi arrotondati vanno riportati al grado successivo.
        if minutes == 60 { minutes = 0; degrees += 1 }
        return "\(degrees)°\(String(format: "%02d", minutes))'" + (value >= 0 ? positive : negative)
    }

    /// "19°48'N".
    public static func latitude(_ c: Coordinate) -> String {
        sexagesimal(c.latitude, positive: "N", negative: "S")
    }

    /// "70°41'O".
    public static func longitude(_ c: Coordinate) -> String {
        sexagesimal(c.longitude, positive: "E", negative: "O")
    }

    /// "19°48'N · 70°41'O" su una riga sola, dove c'è spazio.
    public static func coordinate(_ c: Coordinate) -> String {
        "\(latitude(c)) · \(longitude(c))"
    }

    /// Quante volte ci sta una cosa dentro un'altra: "0,4×", "3,2×", "68×".
    ///
    /// Sotto le dieci volte si tiene un decimale, sopra no: "68,3 volte il Canale
    /// della Manica" finge una precisione che il paragone non ha.
    public static func multiplier(_ value: Double, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = value < 10 ? 1 : 0
        return (f.string(from: NSNumber(value: value)) ?? "0") + "×"
    }

    // MARK: Date, sempre in ora di bordo

    /// "mer 18 nov".
    public static func dayMonth(_ date: Date, clock: ShipClock, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = clock.timeZone(at: date)
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: date)
    }

    /// "MER" per la colonna del giorno nell'itinerario.
    public static func weekdayAbbreviation(_ date: Date, clock: ShipClock, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = clock.timeZone(at: date)
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date).uppercased(with: locale)
    }

    /// "18" per il numero del giorno.
    public static func dayNumber(_ date: Date, clock: ShipClock, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = clock.timeZone(at: date)
        f.setLocalizedDateFormatFromTemplate("d")
        return f.string(from: date)
    }

    /// "09:00 → 18:00" per una sosta.
    /// "15 – 22 novembre 2025", con l'anno una volta sola quando non cambia.
    public static func dateRange(from: Date, to: Date, clock: ShipClock,
                                 locale: Locale = .current) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        // Un intervallo ha un formattatore solo: si prende l'orologio dell'inizio.
        // È l'unica approssimazione della scaletta, e vale mezzanotte una volta
        // l'anno; `window` invece scrive i due estremi uno per uno, ognuno col suo.
        formatter.timeZone = clock.timeZone(at: from)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: from, to: to)
    }

    public static func window(from: Date, to: Date?, clock: ShipClock, locale: Locale = .current) -> String {
        guard let to else { return clock.time(from, locale: locale) }
        return "\(clock.time(from, locale: locale)) → \(clock.time(to, locale: locale))"
    }

    /// "9h" oppure "9h 30" per la durata di una sosta.
    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(String(format: "%02d", minutes))"
    }
}
