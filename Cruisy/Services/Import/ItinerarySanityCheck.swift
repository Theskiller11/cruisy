import Foundation

/// Controlli di buon senso su un itinerario appena letto.
///
/// Il lettore legge riga per riga e non vede l'insieme: un porto sbagliato dall'altra
/// parte del mondo, una partenza prima dell'arrivo, un giorno perso per strada. Qui si
/// guarda la crociera intera e si **segnala** quello che non torna, senza correggere
/// niente: dice che qualcosa è strano, e la correzione la fa chi ha il programma di
/// bordo in mano.
enum ItinerarySanityCheck {

    /// Oltre questa velocità una nave da crociera non va: le più veloci tengono 22–24
    /// nodi. Col margine per gli orari mancanti, stimati, e i fusi ignorati nel conto.
    static let maximumPlausibleKnots = 30.0

    static func run(_ draft: inout ItineraryDraft) {
        checkTimes(&draft.calls)
        checkOrderAndLegs(&draft.calls)
        draft.warnings = warnings(for: draft)
    }

    // MARK: Orari dentro una tappa

    private static func checkTimes(_ calls: inout [DraftCall]) {
        for index in calls.indices where !calls[index].isSeaDay {
            let call = calls[index]
            var wrong = false
            if let arrival = call.arrival, let departure = call.departure, departure <= arrival {
                wrong = true
            }
            // Un all aboard dopo la partenza, o più di tre ore prima, non è un all aboard.
            if let aboard = call.allAboard, let departure = call.departure,
               aboard > departure || departure.minutes - aboard.minutes > 180 {
                wrong = true
            }
            if wrong { calls[index].issues.insert(.timesOutOfOrder) }
        }
    }

    // MARK: Da una tappa all'altra

    private static func checkOrderAndLegs(_ calls: inout [DraftCall]) {
        var previous: (index: Int, date: Date)?
        for index in calls.indices {
            guard let date = midnight(of: calls[index]) else { continue }
            if let previous, date < previous.date {
                calls[index].issues.insert(.dateOutOfOrder)
                continue
            }
            previous = (index, date)
        }

        let ports = calls.indices.filter { !calls[$0].isSeaDay && calls[$0].port != nil }
        for (a, b) in zip(ports, ports.dropFirst()) {
            guard let from = calls[a].port, let to = calls[b].port,
                  let leave = instant(calls[a], calls[a].departure, fallbackHour: 18),
                  let reach = instant(calls[b], calls[b].arrival, fallbackHour: 8) else { continue }
            let hours = reach.timeIntervalSince(leave) / 3600
            let miles = Geo.nauticalMiles(from: from.coordinate, to: to.coordinate)
            guard hours > 0, miles > 5, miles / hours > maximumPlausibleKnots else { continue }
            // Il sospetto va sul porto meno sicuro dei due; a parità, su quello d'arrivo.
            let suspect = from.confidence < to.confidence ? a : b
            calls[suspect].issues.insert(.implausibleLeg)
        }
    }

    private static func midnight(of call: DraftCall) -> Date? {
        guard let day = call.day, let month = call.month, let year = call.year else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))
    }

    /// I fusi si ignorano: sbagliano il conto di qualche ora, e la soglia ha il margine.
    private static func instant(_ call: DraftCall, _ time: TimeOfDay?, fallbackHour: Int) -> Date? {
        midnight(of: call).map { $0.addingTimeInterval(Double(time?.minutes ?? fallbackHour * 60) * 60) }
    }

    // MARK: L'itinerario intero

    private static func warnings(for draft: ItineraryDraft) -> [String] {
        var warnings: [String] = []
        let dates = draft.calls.compactMap(midnight(of:))
        if let stated = draft.statedNights, let first = dates.min(), let last = dates.max(),
           let read = Calendar(identifier: .gregorian).dateComponents([.day], from: first, to: last).day,
           read != stated {
            warnings.append(String(localized: "Il documento dice \(stated) notti, ma ne ho lette \(read): controlla che non manchi un giorno."))
        }
        // Le compagnie contano i porti in modi diversi — con o senza imbarco e sbarco —
        // ma in nessun modo ne dichiarano più di quanti ce ne siano: se il documento ne
        // dice di più, qualcuno si è perso.
        if let stated = draft.statedPorts, draft.portCalls.count < stated {
            warnings.append(String(localized: "Il documento dice \(stated) porti, ma ne ho letti \(draft.portCalls.count): controlla che non manchi uno scalo."))
        }
        return warnings
    }
}
