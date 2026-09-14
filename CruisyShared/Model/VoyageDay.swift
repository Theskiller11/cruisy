import Foundation

/// Un giorno del viaggio, come lo si legge nell'itinerario.
///
/// Ricavato, mai memorizzato: se i giorni di mare fossero righe salvate, correggere
/// un orario di partenza li lascerebbe indietro e l'itinerario mentirebbe.
public struct VoyageDay: Identifiable, Hashable, Sendable {

    public enum Content: Hashable, Sendable {
        case port(PortCall)
        case sea(from: PortCall, to: PortCall)
    }

    /// Dove cade rispetto a oggi. Serve alla resa: il passato si attenua, l'oggi
    /// si mette in risalto.
    public enum Standing: Hashable, Sendable {
        case past, today, tomorrow, future
    }

    /// Mezzanotte di bordo del giorno: identifica la riga in modo stabile.
    public var id: Date
    public var date: Date
    /// "giorno 4 di 9", quindi da 1.
    public var number: Int
    public var content: Content
    public var standing: Standing

    public var port: PortCall? {
        if case .port(let call) = content { return call }
        return nil
    }

    public var isSeaDay: Bool {
        if case .sea = content { return true }
        return false
    }
}

public extension Voyage {

    /// L'itinerario giorno per giorno, in ora di bordo.
    func days(at now: Date) -> [VoyageDay] {
        guard let first = calls.first, let last = calls.last else { return [] }

        // Ogni giorno si misura con l'orologio che la nave ha **quella notte**: la
        // scaletta può spostarlo a metà crociera, e un calendario solo per tutti i
        // giorni farebbe scivolare le mezzanotti di un'ora dopo il primo cambio.
        // Il cambio scatta alle 02:00, quindi la mezzanotte di un giorno cade sempre
        // sotto lo scarto vecchio: calcolarla dal cursore è corretto.
        let firstDay = clock.startOfDay(for: first.arrival)
        let lastDay = clock.startOfDay(for: last.arrival)
        let today = clock.startOfDay(for: now)
        let tomorrow = clock.calendar(at: today).date(byAdding: .day, value: 1, to: today)

        var days: [VoyageDay] = []
        var cursor = firstDay
        var number = 1

        while cursor <= lastDay {
            guard let dayEnd = clock.calendar(at: cursor)
                .date(byAdding: .day, value: 1, to: cursor) else { break }

            let standing: VoyageDay.Standing = if cursor == today { .today }
                else if cursor == tomorrow { .tomorrow }
                else if cursor < today { .past }
                else { .future }

            // Uno scalo occupa il giorno se la sosta lo tocca, anche solo in parte.
            let berthed = calls.first { $0.arrival < dayEnd && $0.castOff >= cursor }

            if let call = berthed {
                days.append(VoyageDay(id: cursor, date: cursor, number: number,
                                      content: .port(call), standing: standing))
            } else if let leg = leg(covering: cursor, until: dayEnd) {
                days.append(VoyageDay(id: cursor, date: cursor, number: number,
                                      content: .sea(from: leg.0, to: leg.1), standing: standing))
            }

            cursor = dayEnd
            number += 1
        }
        return days
    }

    /// La tratta in navigazione che attraversa un dato giorno, se c'è.
    private func leg(covering dayStart: Date, until dayEnd: Date) -> (PortCall, PortCall)? {
        for (previous, next) in zip(calls, calls.dropFirst())
        where previous.castOff < dayEnd && next.arrival > dayStart {
            return (previous, next)
        }
        return nil
    }

    /// Il giorno corrente, per la riga "giorno 4 di 9".
    func currentDay(at now: Date) -> VoyageDay? {
        days(at: now).first { $0.standing == .today }
    }
}
