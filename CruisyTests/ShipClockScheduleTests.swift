import Testing
import Foundation
@testable import Cruisy

/// La scaletta dei cambi d'orologio.
///
/// È la logica più pericolosa dell'app: se sbaglia di un'ora, l'all aboard sullo
/// schermo è sbagliato di un'ora, e chi la usa resta a terra. Perciò qui non si
/// verifica che "funzioni", si verifica **in quale notte** e **a che ora**.
@Suite("Scaletta dell'ora di bordo")
struct ShipClockScheduleTests {

    /// Un istante scritto come lo si legge: giorno, ora e fuso.
    private func instant(_ year: Int, _ month: Int, _ day: Int,
                         _ hour: Int, _ minute: Int = 0, zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func call(_ name: String, _ zone: String, lat: Double, lon: Double,
                      arrival: Date, departure: Date?) -> PortCall {
        PortCall(name: name, region: "", coordinate: Coordinate(latitude: lat, longitude: lon),
                 timeZoneIdentifier: zone, arrival: arrival, departure: departure)
    }

    /// San Juan sta a UTC−4 tutto l'anno, Cancún a UTC−5: due fusi vicini e senza
    /// ora legale, quindi la prova non dipende dal mese in cui gira.
    private let sanJuan = (zone: "America/Puerto_Rico", lat: 18.46, lon: -66.11)
    private let cancun = (zone: "America/Cancun", lat: 21.16, lon: -86.85)

    // MARK: La notte del cambio

    @Test("Con un giorno di mare l'orologio gira la notte che apre quel giorno")
    func changeHappensOnTheNightThatOpensTheSeaDay() throws {
        // Lunedì in porto a San Juan, martedì in mare, mercoledì arrivo a Cancún.
        let departure = instant(2026, 8, 24, 18, zone: sanJuan.zone)
        let arrival = instant(2026, 8, 26, 8, zone: cancun.zone)
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone), departure: departure),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: arrival, departure: nil)
        ]
        let clock = ShipClock.schedule(for: calls) { _ in nil }

        let change = try #require(clock.nextChange(after: departure))
        #expect(change.secondsFromGMT == -5 * 3600)
        // Le 02:00 di **martedì**, lette con l'orologio vecchio (UTC−4).
        #expect(change.at == instant(2026, 8, 25, 2, zone: sanJuan.zone))

        // Il senso di tutto: martedì a mezzogiorno si è già sull'ora di Cancún.
        let tuesdayNoon = instant(2026, 8, 25, 12, zone: sanJuan.zone)
        #expect(clock.secondsFromGMT(at: tuesdayNoon) == -5 * 3600)
        // E lunedì sera si è ancora su quella di San Juan.
        #expect(clock.secondsFromGMT(at: departure) == -4 * 3600)
    }

    @Test("Senza un giorno di mare intero si gira nella notte prima di attraccare")
    func overnightHopChangesOnTheOnlyNightThereIs() throws {
        // Partenza alle 20:00, arrivo la mattina dopo: non c'è nessun giorno di mare,
        // quindi la notte che apre "l'ultimo giorno di mare" cadrebbe prima ancora di
        // salpare. Si ripiega sull'unica notte disponibile.
        let departure = instant(2026, 8, 24, 20, zone: sanJuan.zone)
        let arrival = instant(2026, 8, 25, 7, zone: cancun.zone)
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone), departure: departure),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: arrival, departure: nil)
        ]
        let clock = ShipClock.schedule(for: calls) { _ in nil }

        let change = try #require(clock.nextChange(after: departure))
        #expect(change.at == instant(2026, 8, 25, 2, zone: sanJuan.zone))
        #expect(change.at > departure && change.at <= arrival)
    }

    @Test("Il cambio cade sempre fra la partenza e l'arrivo, mai fuori")
    func changesAlwaysFallWithinTheCrossing() {
        // Si prova ogni ora di partenza del giorno: è il modo in cui i casi limite
        // — salpare all'una di notte, arrivare alle sei del mattino — vengono fuori
        // da soli invece che a bordo.
        for departureHour in 0..<24 {
            for crossingHours in [6, 14, 26, 50] {
                let departure = instant(2026, 8, 24, departureHour, zone: sanJuan.zone)
                let arrival = departure.addingTimeInterval(Double(crossingHours) * 3600)
                let calls = [
                    call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                         arrival: departure.addingTimeInterval(-8 * 3600), departure: departure),
                    call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                         arrival: arrival, departure: nil)
                ]
                let clock = ShipClock.schedule(for: calls) { _ in nil }
                for change in clock.changes.dropFirst() {
                    // Mai prima di salpare, mai dopo l'attracco. Il caso limite —
                    // una traversata così corta da non contenere nessuna notte —
                    // finisce esattamente sull'arrivo, ed è voluto.
                    #expect(change.at > departure,
                            "cambio prima di salpare, partenza alle \(departureHour)")
                    #expect(change.at <= arrival,
                            "cambio dopo l'attracco, partenza alle \(departureHour)")
                }
            }
        }
    }

    @Test("Fra due porti nello stesso fuso l'orologio non si muove")
    func sameZoneMeansNoChange() {
        let departure = instant(2026, 8, 24, 18, zone: sanJuan.zone)
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone), departure: departure),
            call("Charlotte Amalie", "America/St_Thomas", lat: 18.34, lon: -64.93,
                 arrival: instant(2026, 8, 26, 8, zone: sanJuan.zone), departure: nil)
        ]
        let clock = ShipClock.schedule(for: calls) { _ in nil }
        #expect(clock.changes.count == 1)
        #expect(clock.nextChange(after: departure) == nil)
    }

    // MARK: Le traversate lunghe

    @Test("Su più giorni di mare solo l'ultimo è sull'ora del porto, gli altri in ora nautica")
    func longCrossingUsesNauticalTimeUntilTheLastNight() throws {
        // Cinque notti da un porto a UTC−1 a uno a UTC−5, andando verso ovest.
        let departure = instant(2026, 8, 24, 18, zone: "Atlantic/Cape_Verde")
        let arrival = instant(2026, 8, 30, 8, zone: cancun.zone)
        let calls = [
            call("Mindelo", "Atlantic/Cape_Verde", lat: 16.88, lon: -25.0,
                 arrival: instant(2026, 8, 24, 8, zone: "Atlantic/Cape_Verde"),
                 departure: departure),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: arrival, departure: nil)
        ]
        let voyage = Voyage(shipName: "Prova", clock: ShipClock(secondsFromGMT: 0), calls: calls)
        let clock = voyage.scheduledClock

        let nautical = clock.changes.filter { $0.source == .nautical }
        let ports = clock.changes.filter { $0.source == .portTimeZone }

        #expect(!nautical.isEmpty, "una traversata di cinque notti deve avere ore nautiche")
        #expect(ports.count == 2, "l'ancora iniziale e il cambio per il porto d'arrivo")

        // L'ultimo cambio è quello del porto, ed è l'ultimo in ordine di tempo.
        let last = try #require(clock.changes.last)
        #expect(last.source == .portTimeZone)
        #expect(last.secondsFromGMT == -5 * 3600)

        // Ogni passo nautico vale al massimo un'ora: una nave non sposta l'orologio
        // di due ore in una notte sola.
        for change in nautical {
            #expect(abs(clock.shift(at: change)) <= 3600)
        }

        // Tutte le ore nautiche stanno **prima** del cambio per il porto.
        for change in nautical { #expect(change.at < last.at) }
    }

    @Test("Ogni cambio cade alle 02:00 dell'orologio che c'era prima")
    func everyChangeLandsAtTwoInTheMorning() {
        let departure = instant(2026, 8, 24, 18, zone: "Atlantic/Cape_Verde")
        let calls = [
            call("Mindelo", "Atlantic/Cape_Verde", lat: 16.88, lon: -25.0,
                 arrival: instant(2026, 8, 24, 8, zone: "Atlantic/Cape_Verde"),
                 departure: departure),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: instant(2026, 8, 30, 8, zone: cancun.zone), departure: nil)
        ]
        let clock = Voyage(shipName: "Prova", clock: ShipClock(secondsFromGMT: 0),
                           calls: calls).scheduledClock

        for (index, change) in clock.changes.enumerated().dropFirst() {
            // L'orologio *precedente* è quello con cui si legge "le due di notte":
            // chi va a dormire ha ancora quello al polso.
            let before = clock.changes[index - 1].secondsFromGMT
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: before)!
            let parts = calendar.dateComponents([.hour, .minute], from: change.at)
            #expect(parts.hour == 2 && parts.minute == 0,
                    "cambio alle \(parts.hour ?? -1):\(parts.minute ?? -1) invece che alle 02:00")
        }
    }

    // MARK: L'ora nautica

    @Test("L'ora nautica è uno scarto ogni quindici gradi")
    func nauticalOffsetsFollowTheMeridians() {
        #expect(ShipClock.nauticalOffset(longitude: 0) == 0)
        #expect(ShipClock.nauticalOffset(longitude: -60) == -4 * 3600)
        #expect(ShipClock.nauticalOffset(longitude: 61) == 4 * 3600)
        #expect(ShipClock.nauticalOffset(longitude: -7) == 0)
        #expect(ShipClock.nauticalOffset(longitude: -8) == -3600)
        #expect(ShipClock.nauticalOffset(longitude: 180) == 12 * 3600)
        #expect(ShipClock.nauticalOffset(longitude: -180) == -12 * 3600)
    }

    @Test("Uno scalo senza fuso ripiega sull'ora nautica invece di indovinare")
    func portWithoutAZoneFallsBackToNauticalTime() {
        let call = PortCall(name: "Scritto a mano", region: "",
                            coordinate: Coordinate(latitude: 18, longitude: -66),
                            arrival: .now)
        #expect(ShipClock.offset(for: call) == -4 * 3600)
    }

    // MARK: Chi comanda

    @Test("L'orologio impostato a mano non viene ricalcolato")
    func manualClockSurvives() {
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone),
                 departure: instant(2026, 8, 24, 18, zone: sanJuan.zone)),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: instant(2026, 8, 26, 8, zone: cancun.zone), departure: nil)
        ]
        let manual = ShipClock(secondsFromGMT: 3 * 3600, source: .manual)
        let voyage = Voyage(shipName: "Prova", clock: manual, calls: calls)

        // Chi è a bordo ha sentito l'annuncio: l'annuncio batte il calcolo.
        #expect(voyage.withScheduledClock().clock == manual)
        #expect(voyage.withScheduledClock().clock.secondsFromGMT(at: .now) == 3 * 3600)
    }

    @Test("Lo spostamento di un cambio si legge col segno giusto")
    func shiftReportsDirection() throws {
        let departure = instant(2026, 8, 24, 18, zone: sanJuan.zone)
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone), departure: departure),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: instant(2026, 8, 26, 8, zone: cancun.zone), departure: nil)
        ]
        let clock = ShipClock.schedule(for: calls) { _ in nil }
        let change = try #require(clock.nextChange(after: departure))
        // Verso ovest si guadagna un'ora: l'orologio va **indietro**.
        #expect(clock.shift(at: change) == -3600)
    }

    // MARK: Le crociere salvate prima

    @Test("Una crociera salvata col vecchio orologio si legge ancora")
    func oldArchivesStillDecode() throws {
        // La forma di prima: uno scarto solo, in cima all'oggetto.
        let json = Data(#"{"secondsFromGMT":-14400,"source":"portTimeZone"}"#.utf8)
        let clock = try JSONDecoder().decode(ShipClock.self, from: json)

        #expect(clock.changes.count == 1)
        #expect(clock.secondsFromGMT(at: .now) == -4 * 3600)
        #expect(clock.nextChange(after: .now) == nil)
    }

    @Test("Una scaletta scritta e riletta è la stessa scaletta")
    func scheduleRoundTrips() throws {
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone),
                 departure: instant(2026, 8, 24, 18, zone: sanJuan.zone)),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: instant(2026, 8, 26, 8, zone: cancun.zone), departure: nil)
        ]
        let clock = ShipClock.schedule(for: calls) { _ in nil }
        let data = try JSONEncoder().encode(clock)
        #expect(try JSONDecoder().decode(ShipClock.self, from: data) == clock)
    }

    @Test("Due cambi allo stesso scarto valgono per uno solo")
    func redundantChangesArePruned() {
        let base = Date(timeIntervalSince1970: 1_756_000_000)
        let clock = ShipClock(changes: [
            .init(at: base, secondsFromGMT: -4 * 3600, source: .portTimeZone),
            .init(at: base.addingTimeInterval(86_400), secondsFromGMT: -4 * 3600, source: .nautical),
            .init(at: base.addingTimeInterval(172_800), secondsFromGMT: -5 * 3600, source: .portTimeZone)
        ])
        // Senza la potatura, l'avviso "stanotte l'orologio si sposta" comparirebbe
        // anche per la notte in cui non si sposta niente.
        #expect(clock.changes.count == 2)
    }

    @Test("L'avviso annuncia le 02:00, non l'01:59")
    func changeIsAnnouncedAtTwo() throws {
        let departure = instant(2026, 8, 24, 18, zone: sanJuan.zone)
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone), departure: departure),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: instant(2026, 8, 26, 8, zone: cancun.zone), departure: nil)
        ]
        let clock = ShipClock.schedule(for: calls) { _ in nil }
        let change = try #require(clock.nextChange(after: departure))

        // Con l'orologio *nuovo* quell'istante è l'una di notte, e annunciarlo così
        // direbbe un'ora a cui non succede niente.
        let announced = clock.timeBeforeChange(change, locale: Locale(identifier: "it_IT"))
        #expect(announced == "02:00", "annunciato \(announced)")
        #expect(clock.time(change.at, locale: Locale(identifier: "it_IT")) == "01:00")
    }

    // MARK: Le crociere che c'erano già

    @Test("Una crociera salvata senza fusi li recupera e riallinea l'orologio")
    func existingVoyageGetsZonesBackfilled() throws {
        // Com'era in archivio prima di oggi: nessun fuso sugli scali, un orologio
        // a scarto unico. Senza il recupero la scaletta non si accende mai, e la
        // funzione esisterebbe solo per chi importa una crociera da adesso in poi.
        let calls = [
            PortCall(name: "San Juan", region: "", 
                     coordinate: Coordinate(latitude: sanJuan.lat, longitude: sanJuan.lon),
                     arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone),
                     departure: instant(2026, 8, 24, 18, zone: sanJuan.zone)),
            PortCall(name: "Cancún", region: "",
                     coordinate: Coordinate(latitude: cancun.lat, longitude: cancun.lon),
                     arrival: instant(2026, 8, 26, 8, zone: cancun.zone))
        ]
        let vecchia = Voyage(shipName: "Prova",
                             clock: ShipClock(secondsFromGMT: 0), calls: calls)
        #expect(vecchia.calls.allSatisfy { $0.timeZoneIdentifier == nil })
        #expect(vecchia.clock.changes.count == 1)

        let riconciliata = vecchia.reconciled { call in
            call.name == "San Juan" ? sanJuan.zone : cancun.zone
        }
        #expect(riconciliata.calls.allSatisfy { $0.timeZoneIdentifier != nil })
        #expect(riconciliata.clock.changes.count == 2, "l'orologio deve essersi mosso")
        #expect(riconciliata.clock.secondsFromGMT(at: calls[1].arrival) == -5 * 3600)
    }

    @Test("Riconciliare due volte non cambia niente la seconda")
    func reconcilingIsIdempotent() {
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone),
                 departure: instant(2026, 8, 24, 18, zone: sanJuan.zone)),
            call("Cancún", cancun.zone, lat: cancun.lat, lon: cancun.lon,
                 arrival: instant(2026, 8, 26, 8, zone: cancun.zone), departure: nil)
        ]
        // Gira a ogni caricamento e a ogni correzione: se non fosse idempotente,
        // l'orologio si sposterebbe un po' ogni volta che apri l'app.
        let una = Voyage(shipName: "Prova", clock: ShipClock(secondsFromGMT: 0), calls: calls)
            .reconciled { $0.timeZoneIdentifier }
        let due = una.reconciled { $0.timeZoneIdentifier }
        #expect(una.clock == due.clock)
        #expect(una.calls == due.calls)
    }

    @Test("Il recupero dei fusi non tocca uno scalo che ce l'ha già")
    func backfillLeavesKnownZonesAlone() {
        let calls = [
            call("San Juan", sanJuan.zone, lat: sanJuan.lat, lon: sanJuan.lon,
                 arrival: instant(2026, 8, 24, 8, zone: sanJuan.zone),
                 departure: instant(2026, 8, 24, 18, zone: sanJuan.zone)),
            PortCall(name: "Scritto a mano", region: "",
                     coordinate: Coordinate(latitude: 21, longitude: -87),
                     arrival: instant(2026, 8, 26, 8, zone: cancun.zone))
        ]
        let voyage = Voyage(shipName: "Prova", clock: ShipClock(secondsFromGMT: 0), calls: calls)
            .withPortTimeZones { _ in "Europe/Rome" }
        #expect(voyage.calls[0].timeZoneIdentifier == sanJuan.zone, "non si sovrascrive")
        #expect(voyage.calls[1].timeZoneIdentifier == "Europe/Rome", "si riempie il buco")
    }
}
