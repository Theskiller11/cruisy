import Foundation

/// Un traguardo marino a cui paragonare le miglia percorse.
///
/// «1.216 miglia nautiche» non dice niente a nessuno. «Un terzo di una traversata
/// atlantica» sì: è la stessa idea per cui un'app di voli dice quante volte hai
/// fatto il giro del mondo invece di darti i chilometri e basta.
///
/// I traguardi sono **marini di proposito**. Il giro della Terra all'equatore è la
/// misura giusta per un aereo, non per una nave: nessuno naviga sull'equatore.
public struct Milestone: Hashable, Sendable, Identifiable {
    public let name: String
    public let detail: String
    public let nauticalMiles: Double
    public let glyph: String

    public var id: String { name }

    public init(name: String, detail: String, nauticalMiles: Double, glyph: String) {
        self.name = name
        self.detail = detail
        self.nauticalMiles = nauticalMiles
        self.glyph = glyph
    }

    /// La scala, dal più corto al più lungo.
    ///
    /// Le distanze sono rotte reali, non linee rette su una carta: fra Southampton e
    /// New York in linea d'aria ci sono 2.980 miglia, ma nessuna nave passa
    /// sull'Irlanda — la rotta vera ne fa circa 3.100, ed è quella che conta se il
    /// paragone deve essere onesto.
    /// I nomi passano da `String(localized:)`: sono testo che si legge, non dati, e
    /// senza quello restavano in italiano anche con l'app in inglese.
    public static let scale: [Milestone] = [
        .init(name: String(localized: "Il Canale della Manica"),
              detail: String(localized: "Dover → Calais"), nauticalMiles: 18, glyph: "arrow.left.and.right"),
        .init(name: String(localized: "Il Canale di Panama"),
              detail: String(localized: "da oceano a oceano"), nauticalMiles: 43, glyph: "arrow.triangle.merge"),
        .init(name: String(localized: "Da Gibilterra a Palma"),
              detail: String(localized: "lo Stretto → le Baleari"), nauticalMiles: 460, glyph: "sailboat"),
        .init(name: String(localized: "Il Mediterraneo intero"),
              detail: String(localized: "Gibilterra → Beirut"), nauticalMiles: 2_000, glyph: "water.waves"),
        .init(name: String(localized: "La traversata atlantica"),
              detail: String(localized: "Southampton → New York"), nauticalMiles: 3_100, glyph: "globe.europe.africa"),
        .init(name: String(localized: "Il Pacifico"),
              detail: String(localized: "Panama → Sydney"), nauticalMiles: 7_700, glyph: "globe.asia.australia"),
        .init(name: String(localized: "Il giro del mondo"),
              detail: String(localized: "per mare, canali compresi"), nauticalMiles: 25_000, glyph: "globe")
    ]

    /// Quante volte ci sta la distanza percorsa.
    public func times(_ miles: Double) -> Double {
        nauticalMiles > 0 ? miles / nauticalMiles : 0
    }
}

public extension Array where Element == Milestone {

    /// Il traguardo più grande già superato, se ce n'è uno.
    func passed(_ miles: Double) -> Milestone? {
        last { $0.nauticalMiles <= miles }
    }

    /// Il prossimo traguardo da raggiungere.
    func next(after miles: Double) -> Milestone? {
        first { $0.nauticalMiles > miles }
    }

    /// I traguardi da mostrare come paragone: quello attorno a cui si sta adesso.
    ///
    /// Non tutti e sette: «68 volte il Canale della Manica» e «0,00005 volte il giro
    /// del mondo» sono due modi diversi di non dire niente. Si tengono quelli in cui
    /// il numero è leggibile, cioè fra un decimo e cento volte.
    /// - Parameter excluding: il traguardo già mostrato dalla barra. Ripeterlo due
    ///   righe più sotto con lo stesso numero fa sembrare l'elenco un errore.
    func meaningful(for miles: Double, excluding: Milestone? = nil) -> [Milestone] {
        filter { milestone in
            guard milestone != excluding else { return false }
            let times = milestone.times(miles)
            return times >= 0.1 && times <= 100
        }
    }
}

public extension Logbook {

    /// Gli anni in cui c'è stata almeno una crociera, dal più recente.
    func years(calendar: Calendar = Calendar(identifier: .gregorian)) -> [Int] {
        Set(voyages.compactMap { voyage in
            voyage.start.map { calendar.component(.year, from: $0) }
        }).sorted(by: >)
    }

    /// Le miglia di un anno solo, o di sempre se `year` è nullo.
    func nauticalMiles(inYear year: Int?,
                       calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {
        guard let year else { return nauticalMiles }
        return voyages
            .filter { $0.start.map { calendar.component(.year, from: $0) == year } ?? false }
            .reduce(0) { $0 + $1.nauticalMiles }
    }
}
