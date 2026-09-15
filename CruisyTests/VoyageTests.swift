import Testing
import Foundation
@testable import Cruisy

@Suite("Crociera")
struct VoyageTests {

    private let clock = ShipClock(secondsFromGMT: -4 * 3600)
    private let base = Date(timeIntervalSince1970: 1_756_000_000)

    private func hour(_ h: Double) -> Date { base.addingTimeInterval(h * 3600) }

    /// Tre scali: imbarco all'ora 0, scalo intermedio dall'ora 30 all'ora 39,
    /// sbarco all'ora 60. Fra l'uno e l'altro restano tratte in navigazione.
    private func voyage() -> Voyage {
        Voyage(shipName: "Prova", clock: clock, calls: [
            PortCall(name: "Partenza", region: "A",
                     coordinate: Coordinate(latitude: 18.47, longitude: -66.11),
                     role: .embarkation, arrival: hour(0), departure: hour(6), allAboard: hour(5)),
            PortCall(name: "Scalo", region: "B",
                     coordinate: Coordinate(latitude: 19.79, longitude: -70.69),
                     role: .port, arrival: hour(30), departure: hour(39), allAboard: hour(38)),
            PortCall(name: "Arrivo", region: "C",
                     coordinate: Coordinate(latitude: 25.77, longitude: -80.19),
                     role: .disembarkation, arrival: hour(60)),
        ])
    }

    @Test("Lo stato del viaggio segue gli istanti, estremi compresi")
    func momentsAtBoundaries() {
        let v = voyage()

        #expect(v.moment(at: hour(-1)) == .beforeVoyage(next: v.calls[0]))
        // L'istante esatto dell'attracco conta già come "in porto": è il momento in
        // cui si può scendere.
        #expect(v.moment(at: hour(30)) == .inPort(v.calls[1]))
        #expect(v.moment(at: hour(39)) == .inPort(v.calls[1]))

        if case .atSea(let from, let to) = v.moment(at: hour(20)) {
            #expect(from.name == "Partenza")
            #expect(to.name == "Scalo")
        } else {
            Issue.record("A metà fra due scali si deve essere in navigazione")
        }

        #expect(v.moment(at: hour(61)) == .completed)
    }

    @Test("In porto il countdown punta all'all aboard, e l'anello misura la stessa attesa")
    func focusInPortTargetsAllAboard() throws {
        let v = voyage()
        let focus = try #require(v.focus(at: hour(33)))

        guard case .allAboard(let call) = focus.kind else {
            Issue.record("In porto il countdown deve puntare all'all aboard")
            return
        }
        #expect(call.name == "Scalo")
        #expect(focus.countdown.target == hour(38))
        // Il punto dell'audit: l'anello parte dall'attracco, non dalla mezzanotte
        // né dalla partenza, perché deve misurare lo stesso evento del numero.
        #expect(focus.countdown.start == hour(30))
    }

    @Test("Passato l'all aboard il countdown passa alla partenza, non sparisce")
    func focusFallsBackToDeparture() throws {
        let v = voyage()
        let focus = try #require(v.focus(at: hour(38.5)))
        guard case .sailAway = focus.kind else {
            Issue.record("Dopo l'all aboard resta la partenza")
            return
        }
        #expect(focus.countdown.target == hour(39))
    }

    @Test("In navigazione il countdown punta all'arrivo, da quando si è mollato l'ormeggio")
    func focusAtSeaTargetsArrival() throws {
        let v = voyage()
        let focus = try #require(v.focus(at: hour(20)))
        guard case .arrival(let call) = focus.kind else {
            Issue.record("In mare il countdown deve puntare all'arrivo")
            return
        }
        #expect(call.name == "Scalo")
        #expect(focus.countdown.start == hour(6))
        #expect(focus.countdown.target == hour(30))
    }

    @Test("A crociera conclusa non c'è più niente da contare")
    func noFocusWhenCompleted() {
        #expect(voyage().focus(at: hour(70)) == nil)
    }

    /// Una crociera con una traversata lunga: fra la partenza e lo scalo passa più
    /// di un giorno intero, quindi esiste un giorno che nessuno scalo tocca.
    ///
    /// Serve una fixture a parte perché nella crociera corta ogni tratta dura meno di
    /// ventiquattr'ore, e un giorno in cui la nave molla l'ormeggio la mattina resta
    /// giustamente un giorno di porto: è così che si leggono gli itinerari.
    private func longCrossingVoyage() -> Voyage {
        Voyage(shipName: "Traversata", clock: clock, calls: [
            PortCall(name: "Partenza", region: "A",
                     coordinate: Coordinate(latitude: 18.47, longitude: -66.11),
                     role: .embarkation, arrival: hour(0), departure: hour(6), allAboard: hour(5)),
            PortCall(name: "Scalo", region: "B",
                     coordinate: Coordinate(latitude: 28.13, longitude: -15.43),
                     role: .port, arrival: hour(96), departure: hour(105), allAboard: hour(104)),
            PortCall(name: "Arrivo", region: "C",
                     coordinate: Coordinate(latitude: 36.14, longitude: -5.35),
                     role: .disembarkation, arrival: hour(130)),
        ])
    }

    @Test("I giorni di mare nascono dai buchi fra gli scali")
    func seaDaysAreDerived() {
        let days = longCrossingVoyage().days(at: hour(50))
        #expect(days.isEmpty == false)
        #expect(days.contains { $0.isSeaDay })
        // Nessun giorno resta senza contenuto: ogni riga dell'itinerario dice qualcosa.
        #expect(days.allSatisfy { $0.port != nil || $0.isSeaDay })
        // I numeri di giorno sono progressivi e partono da uno.
        #expect(days.first?.number == 1)
    }

    @Test("Esattamente un giorno è oggi")
    func exactlyOneToday() {
        #expect(voyage().days(at: hour(33)).filter { $0.standing == .today }.count == 1)
        #expect(longCrossingVoyage().days(at: hour(50)).filter { $0.standing == .today }.count == 1)
    }

    @Test("Un giorno in cui si molla l'ormeggio resta un giorno di porto")
    func partialStayStillCountsAsPort() {
        // La nave parte alle 6 del mattino e naviga fino a sera: l'itinerario di una
        // compagnia chiamerebbe comunque quel giorno col nome del porto, non "giorno
        // di mare". Il modello deve leggersi come lo leggerebbe chi è a bordo.
        let days = voyage().days(at: hour(20))
        #expect(days.allSatisfy { $0.port != nil })
    }

    @Test("La posizione dagli orari sta fra i due porti e si muove nel tempo")
    func scheduledFixInterpolates() throws {
        let v = voyage()
        let early = try #require(v.scheduledFix(at: hour(10)))
        let late = try #require(v.scheduledFix(at: hour(28)))

        #expect(early.origin == .schedule)
        // Ci si avvicina alla meta, non ci si allontana.
        let target = v.calls[1].coordinate
        #expect(Geo.nauticalMiles(from: late.coordinate, to: target)
                < Geo.nauticalMiles(from: early.coordinate, to: target))
    }

    @Test("In porto la posizione dagli orari è ferma sul molo")
    func scheduledFixInPortIsStill() throws {
        let v = voyage()
        let fix = try #require(v.scheduledFix(at: hour(33)))
        #expect(fix.speed == 0)
        #expect(abs(fix.coordinate.latitude - v.calls[1].coordinate.latitude) < 1e-9)
    }

    @Test("Gli scali si riordinano da soli, comunque li si inserisca")
    func callsAreSorted() {
        let v = voyage()
        let shuffled = Voyage(shipName: "Prova", clock: clock, calls: v.calls.reversed())
        #expect(shuffled.calls.map(\.name) == ["Partenza", "Scalo", "Arrivo"])
    }
}

/// La soglia fra "attesa" e "viaggio".
@Suite("Soglia della vista normale")
@MainActor
struct DepartureThresholdTests {

    private func store(hoursBeforeBoarding hours: Double) -> VoyageStore {
        let now = Date()
        // Imbarco fra `hours` ore, sbarco una settimana dopo.
        let boarding = now.addingTimeInterval(hours * 3600)
        let clock = ShipClock(secondsFromGMT: -4 * 3600)
        let voyage = Voyage(shipName: "Prova", clock: clock, calls: [
            PortCall(name: "Partenza", region: "A",
                     coordinate: Coordinate(latitude: 18.47, longitude: -66.11),
                     role: .embarkation, arrival: boarding,
                     departure: boarding.addingTimeInterval(6 * 3600),
                     allAboard: boarding.addingTimeInterval(5 * 3600)),
            PortCall(name: "Arrivo", region: "B",
                     coordinate: Coordinate(latitude: 25.77, longitude: -80.19),
                     role: .disembarkation,
                     arrival: boarding.addingTimeInterval(7 * 86_400)),
        ])
        return VoyageStore(voyage: voyage, now: now, autoload: false)
    }

    @Test("A crociera lontana la schermata resta in attesa")
    func farAwayIsWaiting() {
        #expect(store(hoursBeforeBoarding: 24 * 20).isAwaitingDeparture)
        #expect(store(hoursBeforeBoarding: 13).isAwaitingDeparture)
    }

    @Test("Dodici ore prima si accende la vista normale")
    func twelveHoursSwitchesOver() {
        // La sera prima l'app torna a essere uno strumento.
        #expect(!store(hoursBeforeBoarding: 11).isAwaitingDeparture)
        #expect(!store(hoursBeforeBoarding: 1).isAwaitingDeparture)
    }

    @Test("A crociera iniziata non si torna mai in attesa")
    func neverWaitsOnceUnderway() {
        #expect(!store(hoursBeforeBoarding: -3).isAwaitingDeparture)
        #expect(!store(hoursBeforeBoarding: -48).isAwaitingDeparture)
    }

    @Test("Senza crociera non si è in attesa di niente")
    func emptyStoreIsNotWaiting() {
        #expect(!VoyageStore(voyage: nil, autoload: false).isAwaitingDeparture)
    }
}
