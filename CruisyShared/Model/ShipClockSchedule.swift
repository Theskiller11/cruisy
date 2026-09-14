import Foundation

/// Come si costruisce la scaletta dei cambi d'orologio da un itinerario.
///
/// Le regole sono quelle che tengono le compagnie, e le ha dettate Matteo il
/// 4 settembre 2026:
///
/// 1. **In porto vale l'ora civile del porto.**
/// 2. **L'ultimo giorno di mare prima di uno scalo è già sull'ora di quello scalo.**
///    Il cambio scatta alle 02:00 della notte che *apre* quel giorno. Con un solo
///    giorno di mare fra due porti — lunedì porto, martedì mare, mercoledì arrivo —
///    l'orologio gira nella notte fra lunedì e martedì, e martedì ci si sveglia già
///    sull'ora di mercoledì.
/// 3. **I giorni di mare precedenti stanno in ora nautica**, cioè lo scarto che
///    compete alla longitudine dove ci si trova, e cambiano anch'essi alle 02:00
///    quando si scavalca un meridiano di zona.
///
/// Il cambio è **tutto insieme**: due ore di differenza si fanno in una notte sola,
/// non spalmate su due. È il comportamento più diffuso e il più facile da annunciare.
public extension ShipClock {

    /// L'ora nautica di una longitudine: uno scarto pieno ogni 15 gradi.
    ///
    /// È quello che fa una nave quando è lontana da tutto e non deve ancora
    /// allinearsi a un porto. Serve anche da ripiego per uno scalo digitato a mano
    /// che non sta nell'elenco dei porti: sbaglia al massimo di mezz'ora rispetto
    /// all'ora civile, e non chiede niente a nessuno.
    static func nauticalOffset(longitude: Double) -> Int {
        var value = longitude
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return Int((value / 15).rounded()) * 3600
    }

    /// Lo scarto di uno scalo alla data del suo arrivo.
    ///
    /// La legge del paese conta **qui e una volta sola**: da questo momento in poi
    /// l'ora di bordo è un numero, e non fa l'ora legale a metà oceano.
    static func offset(for call: PortCall) -> Int {
        if let identifier = call.timeZoneIdentifier,
           let zone = TimeZone(identifier: identifier) {
            return zone.secondsFromGMT(for: call.arrival)
        }
        return nauticalOffset(longitude: call.coordinate.longitude)
    }

    /// Le 02:00 del giorno a cui appartiene `date`, lette con lo scarto dato.
    ///
    /// Il giorno si calcola **con l'orologio vecchio**, che è quello che ha in tasca
    /// chi va a dormire: è lui a decidere quale notte è "stanotte".
    static func twoInTheMorning(onDayOf date: Date, offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
        return calendar.startOfDay(for: date).addingTimeInterval(2 * 3600)
    }

    /// Quando gira l'orologio per il porto d'arrivo.
    ///
    /// Le 02:00 che aprono l'ultimo giorno di mare. Se quell'istante cade prima di
    /// salpare — traversata senza un giorno di mare intero — si ripiega sulle 02:00
    /// del giorno d'arrivo; e se **nemmeno quella** sta dentro la traversata, come in
    /// un salto di sei ore fra due porti vicini, si cambia **attraccando**: quando
    /// scendi a terra l'orologio è quello di dove sei, che è l'unica cosa che conta.
    private static func portChange(arrival: Date, after departure: Date, offset: Int) -> Date {
        var moment = twoInTheMorning(onDayOf: arrival.addingTimeInterval(-86_400),
                                     offset: offset)
        if moment <= departure {
            moment = twoInTheMorning(onDayOf: arrival, offset: offset)
        }
        if moment <= departure || moment > arrival { moment = arrival }
        return moment
    }

    /// Costruisce la scaletta per un itinerario.
    ///
    /// - Parameter position: dove si trova la nave a un certo istante, per l'ora
    ///   nautica delle traversate lunghe. Le si passa `voyage.scheduledFix`, che non
    ///   dipende dall'orologio — se dipendesse, questa funzione girerebbe in tondo.
    static func schedule(for calls: [PortCall],
                         position: (Date) -> Coordinate?) -> ShipClock {
        let ordered = calls.sorted { $0.arrival < $1.arrival }
        guard let first = ordered.first else { return ShipClock(secondsFromGMT: 0) }

        var changes = [Change(at: .distantPast, secondsFromGMT: offset(for: first),
                              source: .portTimeZone)]

        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            let current = changes[changes.count - 1].secondsFromGMT
            let target = offset(for: next)
            let departure = previous.castOff
            let arrival = next.arrival
            guard arrival > departure else { continue }

            // Fin dove arrivano le notti in ora nautica. È provvisorio: lo si
            // ricalcola sotto con l'orologio che ci sarà davvero quella notte.
            let limit = portChange(arrival: arrival, after: departure, offset: current)

            var running = current
            var night = twoInTheMorning(onDayOf: departure, offset: current)
            while night <= departure { night.addTimeInterval(86_400) }

            while night < limit {
                if let here = position(night) {
                    let nautical = nauticalOffset(longitude: here.longitude)
                    if nautical != running {
                        // **Al massimo un'ora per notte** in ora nautica, anche quando
                        // il bersaglio è più lontano. Serve a un caso solo, ma reale:
                        // un porto la cui ora civile è distante dalla sua ora nautica
                        // — Lisbona sta a UTC+1 d'estate e alla longitudine −9, cioè
                        // ora nautica UTC−1 — farebbe girare l'orologio di due ore
                        // nella prima notte di traversata. Le navi non lo fanno: si
                        // spostano di un'ora per volta finché non sono allineate.
                        // Il cambio **per il porto d'arrivo** resta invece tutto in
                        // una notte, come chiesto.
                        running += nautical > running
                            ? min(3600, nautical - running)
                            : max(-3600, nautical - running)
                        changes.append(Change(at: night, secondsFromGMT: running,
                                              source: .nautical))
                    }
                }
                // Le 02:00 della notte dopo vanno **ricalcolate con l'orologio nuovo**.
                // Sommare 24 ore secche sembra la stessa cosa e non lo è: dopo un
                // cambio, ventiquattro ore dopo le 02:00 vecchie sono l'una o le tre
                // di notte, e la scaletta scivolerebbe di un'ora a ogni notte. Le 25
                // ore bastano a cadere nel giorno seguente in entrambi i versi, visto
                // che un passo nautico vale al massimo un'ora.
                night = twoInTheMorning(onDayOf: night.addingTimeInterval(25 * 3600),
                                        offset: running)
            }

            // Il cambio per il porto, ora con l'orologio che c'è davvero quella notte
            // e mai prima dell'ultimo cambio già scritto.
            let moment = portChange(arrival: arrival,
                                    after: max(departure, changes[changes.count - 1].at),
                                    offset: running)
            if target != running {
                changes.append(Change(at: moment, secondsFromGMT: target,
                                      source: .portTimeZone))
            }
        }

        return ShipClock(changes: changes)
    }
}

public extension Voyage {

    /// L'orologio che questo itinerario comporta, ricalcolato da capo.
    ///
    /// Non si applica se l'orologio è stato messo a mano: chi è a bordo ha sentito
    /// l'annuncio, e l'annuncio batte qualunque calcolo. È la stessa regola per cui
    /// un orario corretto a mano vince sull'orario pubblicato.
    var scheduledClock: ShipClock {
        ShipClock.schedule(for: calls) { scheduledFix(at: $0)?.coordinate }
    }

    /// Lo stesso itinerario con l'orologio riallineato agli scali.
    func withScheduledClock() -> Voyage {
        guard clock.changes.allSatisfy({ $0.source != .manual }) else { return self }
        var copy = self
        copy.clock = scheduledClock
        return copy
    }
}

public extension Voyage {

    /// Riempie i fusi mancanti degli scali, cercandoli nell'elenco dei porti.
    ///
    /// **Serve alle crociere salvate prima che i fusi esistessero.** Una crociera che
    /// c'era già ha `timeZoneIdentifier` nullo su ogni scalo: senza questo passaggio
    /// l'ora di bordo ripiegherebbe per sempre sull'ora nautica della longitudine, e
    /// tutta la scaletta dei cambi non si accenderebbe mai — cioè la funzione
    /// esisterebbe solo per chi importa una crociera da oggi in poi.
    ///
    /// - Parameter zone: come si trova il fuso di uno scalo. La passa l'app col
    ///   proprio elenco dei porti; `CruisyShared` non lo conosce perché lo usa anche
    ///   il widget, che non ha bisogno di cercare niente.
    func withPortTimeZones(_ zone: (PortCall) -> String?) -> Voyage {
        var copy = self
        for index in copy.calls.indices where copy.calls[index].timeZoneIdentifier == nil {
            copy.calls[index].timeZoneIdentifier = zone(copy.calls[index])
        }
        return copy
    }

    /// La crociera pronta all'uso: fusi riempiti e orologio riallineato.
    ///
    /// È il passaggio che va fatto **a ogni caricamento e a ogni modifica**, non solo
    /// all'importazione. La prima versione lo faceva solo importando, e il risultato
    /// era che su una crociera già in archivio non cambiava assolutamente niente.
    func reconciled(_ zone: (PortCall) -> String?) -> Voyage {
        withPortTimeZones(zone).withScheduledClock()
    }
}
