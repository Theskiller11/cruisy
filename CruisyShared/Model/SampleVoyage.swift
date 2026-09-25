#if DEBUG
import Foundation

/// Dati di prova per anteprime e collaudo. Solo in DEBUG: nel binario spedito non
/// esistono, perché contenuto segnaposto in produzione è motivo di rifiuto.
///
/// La nave è di fantasia di proposito. I porti invece sono reali, perché un porto e
/// le sue coordinate sono fatti geografici; il nome e la livrea di una nave di una
/// compagnia sono materiale di terzi, e non ci servono per provare un countdown.
public enum SampleVoyage {

    /// Fuso dei Caraibi.
    private static let clock = ShipClock(secondsFromGMT: -4 * 3600, source: .portTimeZone)

    /// Uno scalo espresso in ore dall'inizio della crociera invece che in date.
    ///
    /// Così la crociera si può ancorare a piacere rispetto ad *adesso*, e la prova
    /// finisce sempre nello stato che si voleva provare. Con le date agganciate alla
    /// mezzanotte di bordo, invece, lanciare l'app di mattina o di sera dava stati
    /// diversi e le prove non erano ripetibili.
    private struct Stop {
        let name: String, region: String
        /// Il fuso civile del porto: nella crociera vera lo porta `ports.bin`, qui
        /// va scritto a mano perché lo scenario non passa dall'importazione.
        let zone: String
        let lat: Double, lon: Double
        let arrive: Double
        let depart: Double?
        let allAboard: Double?
        let berth: Berth.Kind
    }

    /// Ora 0 = attracco a San Juan, le 14:00 del primo giorno.
    private static let itinerary: [Stop] = [
        .init(name: "San Juan", region: "Porto Rico", zone: "America/Puerto_Rico", lat: 18.4655, lon: -66.1057,
              arrive: 0, depart: 6, allAboard: 5, berth: .dock),
        .init(name: "Charlotte Amalie", region: "Saint Thomas", zone: "America/St_Thomas", lat: 18.3419, lon: -64.9307,
              arrive: 17, depart: 26, allAboard: 25.5, berth: .dock),
        .init(name: "Gustavia", region: "Saint-Barthélemy", zone: "America/St_Barthelemy", lat: 17.8962, lon: -62.8498,
              arrive: 42, depart: 52, allAboard: 51, berth: .tender),
        // fra Gustavia e Puerto Plata c'è un giorno intero senza scali: giorno di mare
        .init(name: "Puerto Plata", region: "Repubblica Dominicana", zone: "America/Santo_Domingo", lat: 19.7934, lon: -70.6884,
              arrive: 91, depart: 100, allAboard: 99.5, berth: .dock),
        .init(name: "Grand Turk", region: "Turks e Caicos", zone: "America/Grand_Turk", lat: 21.4664, lon: -71.1361,
              arrive: 114, depart: 123, allAboard: 122.5, berth: .dock),
        // altro giorno di mare
        .init(name: "Nassau", region: "Bahamas", zone: "America/Nassau", lat: 25.0778, lon: -77.3383,
              arrive: 161, depart: 168, allAboard: 167.5, berth: .dock),
        .init(name: "Miami", region: "Florida", zone: "America/New_York", lat: 25.7743, lon: -80.1937,
              arrive: 185, depart: nil, allAboard: nil, berth: .dock),
    ]

    /// Ancora la crociera a orari di bordo **realistici**: ora 0 è le 14:00 di
    /// quattro giorni fa, quindi ogni scalo cade a un orario plausibile.
    private static func anchoredStart(now: Date) -> Date {
        let calendar = clock.calendar(at: now)
        let midnight = calendar.startOfDay(for: now)
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: midnight) ?? midnight
        return fourDaysAgo.addingTimeInterval(14 * 3600)
    }

    private static func voyage(now: Date) -> Voyage {
        let start = anchoredStart(now: now)
        func instant(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

        let calls = itinerary.enumerated().map { index, stop in
            PortCall(
                name: stop.name,
                region: stop.region,
                coordinate: Coordinate(latitude: stop.lat, longitude: stop.lon),
                timeZoneIdentifier: stop.zone,
                role: index == 0 ? .embarkation
                    : index == itinerary.count - 1 ? .disembarkation : .port,
                arrival: instant(stop.arrive),
                departure: stop.depart.map(instant),
                allAboard: stop.allAboard.map(instant),
                berth: Berth(kind: stop.berth, name: stop.berth == .tender ? nil : "Molo 2"),
                scheduleOrigin: .publishedSchedule)
        }

        // L'orologio si ricava dagli scali, come per una crociera vera: nei Caraibi
        // d'estate non si sposta mai — sono tutti su UTC−4 — ma d'inverno Grand Turk,
        // Nassau e Miami passano a UTC−5 e il cambio compare da solo. Lo scenario
        // deve comportarsi come la realtà, anche quando la realtà è "non succede
        // niente".
        return Voyage(shipName: "Stella Australe", mmsi: "247000000", imo: "9000001",
                      clock: clock, calls: calls).withScheduledClock()
    }

    /// Uno scenario di prova: la crociera e l'istante da cui guardarla.
    ///
    /// L'istante è separato dall'ora vera del Mac perché le due cose non possono
    /// coincidere: gli scali devono cadere a orari plausibili (09:00 → 18:00, non
    /// 00:40 → 09:40) *e* lo scenario deve trovarsi sempre nello stato che si vuole
    /// provare. Si tiene la crociera realistica e si sposta il punto di osservazione.
    public struct Scenario {
        public let voyage: Voyage
        /// Quanto va spostato l'adesso reale per cadere dentro lo scenario.
        public let timeOffset: TimeInterval
    }

    private static func scenario(now: Date, hoursIntoVoyage: Double) -> Scenario {
        let voyage = voyage(now: now)
        let vantage = anchoredStart(now: now).addingTimeInterval(hoursIntoVoyage * 3600)
        return Scenario(voyage: voyage, timeOffset: vantage.timeIntervalSince(now))
    }

    /// In porto a Puerto Plata alle 14:30 di bordo: restano tre ore all'all aboard,
    /// che è lo stato in cui l'app deve dare il meglio.
    public static func inPort(now: Date = .now) -> Scenario {
        scenario(now: now, hoursIntoVoyage: 96.5)
    }

    /// In navigazione, a metà della traversata verso Puerto Plata.
    public static func atSea(now: Date = .now) -> Scenario {
        scenario(now: now, hoursIntoVoyage: 71.5)
    }

    /// Il giorno prima dell'imbarco: countdown preciso, ormai si contano le ore.
    public static func beforeBoarding(now: Date = .now) -> Scenario {
        scenario(now: now, hoursIntoVoyage: -20)
    }

    /// Sei ore all'imbarco: sotto la soglia delle dodici, quindi la vista normale
    /// dev'essere già accesa.
    public static func boardingToday(now: Date = .now) -> Scenario {
        scenario(now: now, hoursIntoVoyage: -6)
    }

    /// Crociera ancora lontana: qui il countdown va detto in giorni, non in ore.
    public static func farFromBoarding(now: Date = .now) -> Scenario {
        scenario(now: now, hoursIntoVoyage: -23 * 24)
    }

    /// La crociera per il collaudo **sul telefono**.
    ///
    /// Diversa dalle altre di proposito. Le altre spostano il punto di osservazione,
    /// e va bene in app — ma widget e Live Activity girano in un altro processo, con
    /// l'ora vera: lo scarto non lo vedono. Quindi qui gli orari sono ancorati
    /// all'**adesso reale**, e l'ora di bordo è quella del telefono, così non compare
    /// nemmeno la striscia del fuso disallineato a confondere la prova.
    ///
    /// Risultato: attraccata cinque ore fa, all aboard fra tre ore, partenza fra tre
    /// e mezza. È lo stato in cui il widget ha qualcosa da contare e la Live Activity
    /// si può accendere: proprio al limite delle tre ore della sua finestra in porto.
    public static func deviceTest(now: Date = .now) -> Scenario {
        let clock = ShipClock(secondsFromGMT: TimeZone.current.secondsFromGMT(for: now),
                              source: .manual)
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }

        let voyage = Voyage(
            shipName: "Prova di bordo", mmsi: "247000000", clock: clock,
            calls: [
                PortCall(name: "San Juan", region: "Puerto Rico",
                         coordinate: Coordinate(latitude: 18.4655, longitude: -66.1057),
                         role: .embarkation,
                         arrival: at(-48), departure: at(-42), allAboard: at(-43)),
                PortCall(name: "Puerto Plata", region: "Repubblica Dominicana",
                         coordinate: Coordinate(latitude: 19.7934, longitude: -70.6884),
                         role: .port,
                         arrival: at(-5), departure: at(3.5), allAboard: at(3),
                         berth: Berth(kind: .dock, name: "Amber Cove")),
                PortCall(name: "Grand Turk", region: "Turks e Caicos",
                         coordinate: Coordinate(latitude: 21.4664, longitude: -71.1361),
                         role: .port,
                         arrival: at(20), departure: at(29), allAboard: at(28.5)),
                PortCall(name: "Miami", region: "Florida",
                         coordinate: Coordinate(latitude: 25.7743, longitude: -80.1937),
                         role: .disembarkation, arrival: at(50)),
            ],
            updatedAt: now)
        // Nessuno scarto: l'ora vera va già bene.
        return Scenario(voyage: voyage, timeOffset: 0)
    }

    /// Venti minuti all'all aboard: lo stato limite, quello che va provato più di tutti.
    public static func allAboardImminent(now: Date = .now) -> Scenario {
        scenario(now: now, hoursIntoVoyage: 99.5 - (20.0 / 60.0))
    }

    // MARK: Una crociera passata, per il Diario

    /// Una crociera del maggio 2025 nel Mediterraneo, già nel diario, con la rotta
    /// registrata e un buco: fra Ajaccio e Portofino il telefono era spento.
    ///
    /// Serve a provare la pagina di una crociera conclusa, che con la sola crociera
    /// di prova — sempre in corso — non si vedrebbe mai.
    public static func pastCruise() -> LoggedVoyage {
        let clock = ShipClock(secondsFromGMT: 2 * 3600, source: .portTimeZone)
        // 3 maggio 2025, 16:00 a bordo.
        let embark = Date(timeIntervalSince1970: 1_746_280_800)
        let hour = 3600.0
        let stops: [(String, String, Double, Double, Double)] = [
            ("Barcellona", "Spagna", 41.3775, 2.1830, 0),
            ("Palma", "Spagna", 39.5588, 2.6360, 16),
            ("Ajaccio", "Francia", 41.9192, 8.7386, 64),
            ("Portofino", "Italia", 44.3030, 9.2098, 87),
            ("Civitavecchia", "Italia", 42.0931, 11.7903, 135),
        ]
        let ports = stops.map { LoggedPort(name: $0.0, region: $0.1,
                                           coordinate: Coordinate(latitude: $0.2, longitude: $0.3),
                                           arrival: embark + $0.4 * hour) }
        // Punti di passaggio fra un porto e l'altro, per una rotta che non tagli
        // le isole. Il terzo tratto si ferma a Capo Corso: lì il telefono si spegne.
        let legs: [[(Double, Double)]] = [
            [(41.25, 2.35), (40.55, 2.55), (39.75, 2.62)],
            [(39.45, 3.4), (39.55, 5.2), (40.3, 6.9), (41.2, 8.2), (41.75, 8.6)],
            [(42.15, 8.5), (42.7, 8.65), (43.05, 9.3)],
            [(44.1, 9.55), (43.6, 10.05), (43.0, 10.35), (42.5, 10.9), (42.2, 11.5)],
        ]
        var points: [TrackPoint] = []
        for (index, waypoints) in legs.enumerated() {
            let from = ports[index], to = ports[index + 1]
            let leave = from.arrival + 9 * hour
            let arrive = to.arrival - 0.5 * hour
            var path = [from.coordinate] + waypoints.map { Coordinate(latitude: $0.0, longitude: $0.1) }
            if index != 2 { path.append(to.coordinate) }
            let steps = max(1, Int(arrive.timeIntervalSince(leave) / 600))
            // Una velocità costante lungo la spezzata: un punto ogni dieci minuti.
            let lengths = zip(path, path.dropFirst()).map { Geo.nauticalMiles(from: $0, to: $1) }
            let total = lengths.reduce(0, +)
            let end = index == 2 ? leave + 4 * hour : arrive
            let count = index == 2 ? 24 : steps
            for step in 0...count {
                var travelled = total * Double(step) / Double(count)
                var segment = 0
                while segment < lengths.count - 1, travelled > lengths[segment] {
                    travelled -= lengths[segment]
                    segment += 1
                }
                let t = lengths[segment] > 0 ? min(travelled / lengths[segment], 1) : 0
                let a = path[segment], b = path[segment + 1]
                points.append(TrackPoint(
                    coordinate: Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                           longitude: a.longitude + (b.longitude - a.longitude) * t),
                    at: leave + end.timeIntervalSince(leave) * Double(step) / Double(count)))
            }
        }
        let track = Track(points: points)
        var entry = LoggedVoyage(id: UUID(uuidString: "5E1F0000-0000-4000-8000-000000002025")!,
                                 shipName: "Stella Polare", ports: ports,
                                 nauticalMiles: 0, seaDays: 2, secondsFromGMT: clock.secondsFromGMT(at: embark),
                                 track: track)
        entry.nauticalMiles = entry.legs(track: track).reduce(0) { $0 + $1.nauticalMiles }
        return entry
    }
}
#endif
