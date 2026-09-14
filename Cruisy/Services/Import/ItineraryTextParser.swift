import Foundation

/// Legge un itinerario da testo libero, senza modelli e senza rete.
///
/// È l'unico lettore dell'app. A parità di ingresso dà sempre lo stesso risultato,
/// quindi si può collaudare riga per riga, e funziona su qualunque iPhone senza
/// dipendere da un modello che può non esserci: una strada sviluppata bene batte due
/// sviluppate a metà.
///
/// Lavora **a blocchi**, non a righe. Un blocco comincia dove compare una data e si
/// prende tutto quello che segue fino alla data successiva:
///
///     Sabato 15 novembre
///     San Juan, Porto Rico
///     Imbarco 14:00 · Partenza 20:00
///
/// Con la lettura riga per riga, qui la data non trovava un porto e il porto non
/// trovava una data. A blocchi, il contesto fra una tappa e l'altra viene assorbito
/// dalla tappa a cui appartiene invece di mandare tutto in confusione.
struct ItineraryTextParser {

    /// Quante righe senza data un blocco può assorbire prima di smettere.
    /// Serve a non far inghiottire a una tappa un paragrafo di prosa.
    private static let maximumBlockLines = 7

    // MARK: Vocabolario

    private static let monthNames: [String: Int] = {
        let italian = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
                       "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
        let english = ["january", "february", "march", "april", "may", "june",
                       "july", "august", "september", "october", "november", "december"]
        var table: [String: Int] = [:]
        for (index, name) in (italian + english).enumerated() {
            let month = index % 12 + 1
            table[name] = month
            table[String(name.prefix(3))] = month
        }
        table["sett"] = 9; table["sept"] = 9; table["giu"] = 6; table["lug"] = 7
        return table
    }()

    /// I giorni della settimana vengono **cancellati prima** di cercare la data.
    ///
    /// Senza, "Mar 17" diventava il 17 marzo invece di martedì 17 — e con esso
    /// saltava tutta la crociera. Le abbreviazioni dei giorni collidono con quelle
    /// dei mesi in tutte e due le lingue: mar/marzo, mar/March, mag/maggio, may.
    private static let weekdayWords: Set<String> = [
        "lunedi", "martedi", "mercoledi", "giovedi", "venerdi", "sabato", "domenica",
        "lun", "mar", "mer", "gio", "ven", "sab", "dom",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
    ]

    private static let seaDayWords = ["giorno di mare", "giornata di mare", "in navigazione",
                                      "navigazione", "day at sea", "at sea", "sea day",
                                      "cruising", "in mare", "giorno in mare"]
    private static let tenderWords = ["tender", "lancia", "ancoraggio", "anchored", "anchorage"]
    private static let allAboardWords = ["all aboard", "allaboard", "tutti a bordo",
                                         "rientro a bordo", "back on board", "onboard by",
                                         "all on board", "rientro obbligatorio"]

    /// Parole che non fanno parte del nome di un porto.
    private static let noiseWords = [
        "imbarco", "sbarco", "embark", "embarkation", "disembark", "disembarkation",
        "partenza", "arrivo", "depart", "departure", "arrive", "arrival",
        "ormeggio", "banchina", "dock", "docked", "berth", "pier", "molo",
        "tender", "lancia", "ancoraggio", "anchored",
        "all aboard", "tutti a bordo", "rientro a bordo", "rientro obbligatorio",
        "giorno", "giornata", "day", "porto", "port of", "scalo", "tappa",
    ]

    // MARK: Formato numerico del documento

    /// In che ordine questo documento scrive le date numeriche.
    ///
    /// Si decide **una volta per documento**, non riga per riga: "05/11" da solo è
    /// ambiguo, ma se altrove compare "15/11" allora il primo numero è il giorno, e
    /// quella certezza vale per tutto il testo.
    enum NumericOrder: Equatable { case dayFirst, monthFirst }

    static func inferNumericOrder(in text: String) -> NumericOrder {
        var sawDayFirst = false, sawMonthFirst = false
        for match in text.matches(of: #/\b(\d{1,2})[\/.\-](\d{1,2})\b/#) {
            guard let first = Int(match.1), let second = Int(match.2) else { continue }
            if first > 12, second <= 12 { sawDayFirst = true }
            if second > 12, first <= 12 { sawMonthFirst = true }
        }
        if sawDayFirst != sawMonthFirst { return sawDayFirst ? .dayFirst : .monthFirst }
        // Nessuna prova interna: decide la lingua del documento.
        return looksEnglish(text) ? .monthFirst : .dayFirst
    }

    private static func looksEnglish(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let english = ["embark", "depart", "arrive", "at sea", "aboard", "january", "february",
                       "august", "september", "october", "november", "december", "monday", "friday"]
        let italian = ["imbarco", "partenza", "arrivo", "giorno di mare", "bordo", "gennaio",
                       "febbraio", "agosto", "settembre", "ottobre", "novembre", "dicembre",
                       "lunedi", "venerdi", "ormeggio"]
        let englishHits = english.count { lowered.contains($0) }
        let italianHits = italian.count { lowered.contains($0) }
        return englishHits > italianHits
    }

    // MARK: Ingresso

    func parse(_ text: String) -> ItineraryDraft {
        var draft = ItineraryDraft()
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        draft.shipName = shipName(in: lines)

        let order = Self.inferNumericOrder(in: text)
        draft.calls = blocks(from: lines, order: order).compactMap { call(from: $0, order: order) }

        resolveMonths(&draft.calls)
        resolveYears(&draft.calls)
        PortDisambiguator.resolve(&draft.calls)
        fillAssumedAllAboard(&draft.calls)
        return draft
    }

    // MARK: Nome della nave

    private func shipName(in lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let lowered = line.lowercased()
            if let range = lowered.range(of: #"(?:nave|ship|m/?[nsv])[:\s]+"#,
                                         options: .regularExpression) {
                let name = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        // Nessuna etichetta: la prima riga breve senza cifre è il candidato migliore.
        for line in lines.prefix(3) where !line.contains(where: \.isNumber) {
            if line.count <= 40, line.count >= 3 { return line }
        }
        return nil
    }

    // MARK: Blocchi

    private struct Block {
        var lines: [String]
        var date: FoundDate
        /// La riga in cui stava la data, e dove va tolta prima di cercare il porto.
        var dateLineIndex: Int
    }

    private func blocks(from lines: [String], order: NumericOrder) -> [Block] {
        var blocks: [Block] = []
        for line in lines {
            if let date = findDate(in: line, order: order) {
                blocks.append(Block(lines: [line], date: date, dateLineIndex: 0))
            } else if !blocks.isEmpty,
                      blocks[blocks.count - 1].lines.count < Self.maximumBlockLines {
                blocks[blocks.count - 1].lines.append(line)
            }
        }
        return blocks
    }

    // MARK: Una tappa

    private func call(from block: Block, order: NumericOrder) -> DraftCall? {
        let joined = block.lines.joined(separator: " ")
        let lowered = joined.lowercased()

        var call = DraftCall(rawName: "", sourceLine: joined)
        call.day = block.date.day
        call.month = block.date.month
        call.year = block.date.year
        call.isSeaDay = Self.seaDayWords.contains { lowered.contains($0) }
        call.berth = Self.tenderWords.contains { lowered.contains($0) } ? .tender : .dock

        // L'all aboard si cerca per primo perché è etichettato: lasciato nel mucchio,
        // verrebbe scambiato per l'orario di partenza.
        var aboard: TimeOfDay?
        var consumedByAboard: [Int: Range<String.Index>] = [:]
        for (index, line) in block.lines.enumerated() {
            if let found = labelledTime(in: line.lowercased(), labels: Self.allAboardWords) {
                aboard = found.time
                consumedByAboard[index] = found.range
                break
            }
        }
        call.allAboard = aboard

        // Gli orari si raccolgono da tutto il blocco, nell'ordine in cui compaiono.
        var schedule: [TimeOfDay] = []
        var residues: [String] = []
        for (index, line) in block.lines.enumerated() {
            var consumed: [Range<String.Index>] = []
            if index == block.dateLineIndex { consumed.append(block.date.range) }
            if let aboardRange = consumedByAboard[index] { consumed.append(aboardRange) }

            let found = times(in: line.lowercased(), excluding: consumed)
            schedule.append(contentsOf: found.map(\.time))
            consumed.append(contentsOf: found.map(\.range))
            residues.append(residue(of: line, removing: consumed))
        }

        if let first = schedule.first { call.arrival = first }
        if schedule.count > 1 { call.departure = schedule[1] }

        if call.isSeaDay { return call }

        // Il nome del porto è il residuo che si aggancia meglio all'elenco: così una
        // riga come "Cabina 11024 · ponte 11", assorbita nel blocco, non può vincere
        // contro quella che contiene davvero il porto.
        var best: (name: String, candidates: [PortMatch])?
        for residue in residues where residue.count >= 3 {
            let candidates = PortGazetteer.shared.candidates(residue)
            guard let top = candidates.first else { continue }
            if best == nil || top.confidence > (best?.candidates.first?.confidence ?? 0) {
                best = (residue, candidates)
            }
        }

        if let best {
            call.rawName = best.name
            call.portCandidates = best.candidates
            if call.portCandidates.count == 1 { call.port = best.candidates[0] }
            if best.candidates[0].confidence < 0.9 { call.issues.insert(.portUncertain) }
        } else {
            call.rawName = residues.first { !$0.isEmpty } ?? ""
        }

        if schedule.isEmpty { call.issues.insert(.missingTimes) }

        // Un blocco senza porto riconosciuto **e** senza orari è prosa con dentro una
        // data — un numero di prenotazione, un ringraziamento. Si scarta in silenzio
        // invece di presentarlo come una riga da sistemare: un avviso falso toglie
        // peso a quelli veri.
        guard !call.portCandidates.isEmpty || !schedule.isEmpty else { return nil }
        if call.portCandidates.isEmpty { call.issues.insert(.portUnknown) }
        return call
    }

    // MARK: Date

    private struct FoundDate {
        var day: Int
        /// Nullo quando la riga dice solo il giorno: il mese si eredita dalla tappa
        /// precedente.
        var month: Int?
        var year: Int?
        var range: Range<String.Index>
    }

    /// Sostituisce i giorni della settimana con spazi, **mantenendo la lunghezza**.
    ///
    /// Così le posizioni trovate dalle espressioni regolari restano valide sulla riga
    /// originale, e non serve tenere due stringhe allineate a mano.
    private func blankingWeekdays(_ line: String) -> (blanked: String, hadWeekday: Bool) {
        var result = ""
        var hadWeekday = false
        var token = ""

        func flush() {
            let folded = token.folding(options: .diacriticInsensitive, locale: nil).lowercased()
            if Self.weekdayWords.contains(folded) {
                result += String(repeating: " ", count: token.count)
                hadWeekday = true
            } else {
                result += token
            }
            token = ""
        }

        for character in line {
            if character.isLetter { token.append(character) } else { flush(); result.append(character) }
        }
        flush()
        return (result, hadWeekday)
    }

    private func findDate(in line: String, order: NumericOrder) -> FoundDate? {
        let (blanked, hadWeekday) = blankingWeekdays(line)
        let text = blanked.lowercased()

        // "2026-11-15"
        if let m = text.firstMatch(of: #/\b(\d{4})-(\d{1,2})-(\d{1,2})\b/#) {
            if let year = Int(m.1), let month = Int(m.2), let day = Int(m.3),
               (1...12).contains(month), (1...31).contains(day) {
                return FoundDate(day: day, month: month, year: year, range: m.range)
            }
        }
        // "15/11", "15-11-2026", "11.15.26"
        if let m = text.firstMatch(of: #/\b(\d{1,2})[\/.\-](\d{1,2})(?:[\/.\-](\d{2,4}))?\b/#) {
            if let first = Int(m.1), let second = Int(m.2) {
                let day = order == .dayFirst ? first : second
                let month = order == .dayFirst ? second : first
                if (1...31).contains(day), (1...12).contains(month) {
                    var year: Int?
                    if let raw = m.3, let value = Int(raw) { year = value < 100 ? 2000 + value : value }
                    return FoundDate(day: day, month: month, year: year, range: m.range)
                }
            }
        }
        // "15 nov", "15 novembre 2026", "15th November", "1° maggio"
        if let m = text.firstMatch(of: #/\b(\d{1,2})(?:st|nd|rd|th|º|°)?\s+(?:di\s+)?([a-zàèéìòù]{3,12})\.?(?:,?\s+(\d{4}))?/#) {
            if let month = Self.monthNames[String(m.2)], let day = Int(m.1), (1...31).contains(day) {
                return FoundDate(day: day, month: month, year: m.3.flatMap { Int($0) }, range: m.range)
            }
        }
        // "nov 15", "November 15th, 2026"
        if let m = text.firstMatch(of: #/\b([a-zàèéìòù]{3,12})\.?\s+(\d{1,2})(?:st|nd|rd|th|º|°)?(?:,?\s+(\d{4}))?\b/#) {
            if let month = Self.monthNames[String(m.1)], let day = Int(m.2), (1...31).contains(day) {
                return FoundDate(day: day, month: month, year: m.3.flatMap { Int($0) }, range: m.range)
            }
        }
        // "GIO 20  Grand Turk": solo il giorno, col mese ereditato.
        //
        // Si accetta un numero nudo **soltanto** dopo un giorno della settimana:
        // senza quel segnale, qualunque "11024" di un numero di cabina diventerebbe
        // una data.
        if hadWeekday, let m = text.firstMatch(of: #/^\s*(\d{1,2})(?:st|nd|rd|th|º|°)?\b/#) {
            if let day = Int(m.1), (1...31).contains(day) {
                return FoundDate(day: day, month: nil, year: nil, range: m.range)
            }
        }
        return nil
    }

    // MARK: Orari

    private struct FoundTime {
        var time: TimeOfDay
        var range: Range<String.Index>
    }

    private func times(in text: String, excluding consumed: [Range<String.Index>]) -> [FoundTime] {
        var found: [FoundTime] = []
        for m in text.matches(of: #/\b(\d{1,2})[:.h](\d{2})\s*(am|pm)?/#) {
            guard !consumed.contains(where: { $0.overlaps(m.range) }) else { continue }
            guard let time = TimeOfDay(parsing: String(text[m.range])) else { continue }
            found.append(FoundTime(time: time, range: m.range))
        }
        // "2 pm", "11am": solo col meridiano, altrimenti un numero di ponte o di
        // cabina passerebbe per un orario.
        for m in text.matches(of: #/\b(\d{1,2})\s*(am|pm)\b/#) {
            guard !consumed.contains(where: { $0.overlaps(m.range) }),
                  !found.contains(where: { $0.range.overlaps(m.range) }),
                  let hour = Int(m.1), (1...12).contains(hour) else { continue }
            var normalised = hour
            if m.2 == "pm", hour != 12 { normalised += 12 }
            if m.2 == "am", hour == 12 { normalised = 0 }
            found.append(FoundTime(time: TimeOfDay(hour: normalised, minute: 0), range: m.range))
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Un orario preceduto da un'etichetta come "all aboard".
    private func labelledTime(in text: String, labels: [String]) -> FoundTime? {
        for label in labels {
            guard let labelRange = text.range(of: label) else { continue }
            // Si guarda solo poco dopo l'etichetta: più in là, l'orario è di altro.
            let window = text[labelRange.upperBound...].prefix(16)
            guard let m = window.firstMatch(of: #/(\d{1,2})[:.h](\d{2})\s*(am|pm)?/#),
                  let time = TimeOfDay(parsing: String(window[m.range])) else { continue }
            return FoundTime(time: time, range: labelRange.lowerBound..<window.endIndex)
        }
        return nil
    }

    // MARK: Resto della riga

    private func residue(of line: String, removing ranges: [Range<String.Index>]) -> String {
        var kept = ""
        var index = line.startIndex
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where range.lowerBound >= index {
            kept += line[index..<range.lowerBound]
            index = range.upperBound
        }
        if index < line.endIndex { kept += line[index...] }

        var result = kept
        for word in Self.noiseWords + Array(Self.weekdayWords) {
            result = result.replacingOccurrences(of: "\\b\(word)\\w*\\b", with: " ",
                                                 options: [.regularExpression, .caseInsensitive])
        }
        // Virgole e parentesi si **tengono**: sono i separatori con cui il gazetteer
        // distingue "Charlotte Amalie, St. Thomas" — il porto dall'isola.
        result = result.replacingOccurrences(of: #"[\-–—•·|>→:\[\]]+"#, with: " ",
                                             options: .regularExpression)
        // Numeri isolati rimasti: ponti, cabine, quantità. Mai nomi di porto.
        result = result.replacingOccurrences(of: #"\b\d+\b"#, with: " ",
                                             options: .regularExpression)
        return result.split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Rifiniture su tutta la crociera

    /// Completa i mesi mancanti dalle tappe che dicevano solo il giorno.
    ///
    /// Il mese si eredita da quella prima; se il numero del giorno torna indietro
    /// (dal 30 al 2) vuol dire che è cambiato il mese.
    private func resolveMonths(_ calls: inout [DraftCall]) {
        var lastMonth: Int?
        var lastDay: Int?
        for index in calls.indices {
            guard let day = calls[index].day else { continue }
            if calls[index].month == nil {
                guard var month = lastMonth else { continue }
                if let previous = lastDay, day < previous {
                    month = month == 12 ? 1 : month + 1
                }
                calls[index].month = month
            }
            lastMonth = calls[index].month
            lastDay = day
        }
    }

    /// Decide l'anno guardando l'itinerario intero.
    ///
    /// Gli itinerari quasi mai lo scrivono, e una crociera che scavalca capodanno
    /// prenderebbe due anni diversi. Si parte dal primo anno noto — o dal prossimo in
    /// cui quella data cade nel futuro — e si incrementa quando il mese torna indietro.
    private func resolveYears(_ calls: inout [DraftCall]) {
        guard !calls.isEmpty else { return }
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let thisYear = calendar.component(.year, from: today)

        var year = calls.compactMap(\.year).first ?? {
            guard let first = calls.first, let day = first.day, let month = first.month,
                  let candidate = calendar.date(from: DateComponents(year: thisYear, month: month, day: day))
            else { return thisYear }
            // Una crociera inserita adesso sta nel futuro: se quella data è già
            // passata, si intende l'anno prossimo.
            return candidate < calendar.startOfDay(for: today) ? thisYear + 1 : thisYear
        }()

        var previousMonth: Int?
        for index in calls.indices {
            guard let month = calls[index].month else {
                calls[index].issues.insert(.missingDate); continue
            }
            if let previous = previousMonth, month < previous { year += 1 }
            if let stated = calls[index].year { year = stated } else { calls[index].year = year }
            previousMonth = month
        }
    }

    /// Propone l'all aboard dove il documento non lo dice.
    ///
    /// Conservativo — mezz'ora prima della partenza in banchina, un'ora col tender,
    /// perché con la lancia l'ultima corsa parte prima e c'è la coda — e la riga resta
    /// marchiata, così il riesame la mette in evidenza e chiede conferma. Mai
    /// inventare in silenzio un orario da cui dipende il rientro a bordo.
    private func fillAssumedAllAboard(_ calls: inout [DraftCall]) {
        for index in calls.indices where !calls[index].isSeaDay {
            guard calls[index].allAboard == nil,
                  let departure = calls[index].departure else { continue }
            let lead = calls[index].berth == .tender ? 60 : 30
            calls[index].allAboard = departure.offset(byMinutes: -lead)
            calls[index].issues.insert(.allAboardAssumed)
        }
    }
}
