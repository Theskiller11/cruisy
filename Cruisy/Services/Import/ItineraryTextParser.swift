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
        "ormeggio", "ormeggiata", "banchina", "dock", "docked", "berth", "pier", "molo",
        "tender", "lancia", "ancoraggio", "anchored",
        "all aboard", "tutti a bordo", "rientro a bordo", "rientro obbligatorio",
        "giorno", "giornata", "day", "porto", "port of", "scalo", "tappa",
        "deck", "ponte",
    ]

    /// Le etichette che dicono **quale** orario è. Le compagnie le scrivono quasi
    /// sempre, e sono più affidabili della posizione: al primo giorno Explora scrive
    /// solo «Partenza 17:00», e letto per posizione diventava l'orario d'arrivo.
    /// «Imbarco» sta con l'arrivo: al primo scalo è l'imbarco, negli altri Explora
    /// lo usa proprio per l'arrivo in porto.
    private static let arrivalLabels = ["arrivo", "arrival", "arrive", "arriving", "attracco",
                                        "imbarco", "embark", "boarding", "sbarco", "disembark"]
    /// Anche i verbi: «la nave parte alle 20:00» è una partenza quanto «Partenza 20:00».
    private static let departureLabels = ["partenza", "departure", "depart", "departing",
                                          "sail away", "sailing", "sails", "salpa", "parte",
                                          "leaves"]

    /// Isole e paesi che nei titoli stanno al posto del porto: «Nuovi orizzonti ad
    /// Anguilla» vuol dire Road Bay. Solo quelli con un porto crociere solo e ovvio;
    /// `ItineraryAliasTests` controlla che ognuno esista nell'elenco dei porti.
    static let portAliases: [String: String] = [
        "anguilla": "Road Bay",
        "antigua": "Saint John's",
        "saint croix": "Frederiksted", "st croix": "Frederiksted",
        "saint thomas": "Charlotte Amalie", "st thomas": "Charlotte Amalie",
        "grand cayman": "Georgetown",
        "saint lucia": "Castries", "st lucia": "Castries",
        "barbados": "Bridgetown",
        "aruba": "Oranjestad",
        "curacao": "Willemstad",
        "bonaire": "Kralendijk",
        "saint kitts": "Basseterre", "st kitts": "Basseterre",
    ]

    /// Parole che da sole non sono mai un porto, anche se l'elenco ne ha uno con
    /// quel nome: cercando un porto parola per parola dentro un titolo, «Il mondo
    /// sommerso» non deve diventare un porto chiamato «Mondo».
    private static let windowStopwords: Set<String> = [
        "il", "lo", "la", "le", "gli", "i", "un", "una", "uno", "di", "da", "del", "della",
        "dei", "delle", "al", "alla", "ai", "alle", "ad", "a", "in", "e", "ed", "per", "con",
        "su", "tra", "fra", "the", "of", "and", "to", "at", "on", "for", "with", "from",
        "nave", "ship", "porto", "port", "isola", "island", "isla", "mare", "sea", "baia",
        "bay", "citta", "city", "centro", "spiaggia", "beach", "mondo", "world", "nuovi",
        "nuovo", "grande", "grand", "new", "old", "vecchia", "tour", "viaggio", "journey",
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
            .filter { !$0.isEmpty && !Self.isBoilerplate($0) }

        draft.shipName = shipName(in: lines)

        let order = Self.inferNumericOrder(in: text)
        // L'anno scritto da qualche parte nel documento — in copertina, in un
        // riepilogo — vale per le tappe che scrivono solo giorno e mese.
        let documentYear = lines.lazy.compactMap { findDate(in: $0, order: order)?.year }.first

        var calls = blocks(from: lines, order: order).compactMap { call(from: $0, order: order) }
        calls = mergingDuplicates(calls)
        fillDatesFromDayNumbers(&calls, documentYear: documentYear)
        fillDatesBetweenNeighbours(&calls, documentYear: documentYear)
        draft.calls = calls

        resolveMonths(&draft.calls)
        resolveYears(&draft.calls, documentYear: documentYear)
        PortDisambiguator.resolve(&draft.calls)
        fillAssumedAllAboard(&draft.calls)

        (draft.statedNights, draft.statedPorts) = Self.statedCounts(in: lines)
        ItinerarySanityCheck.run(&draft)
        return draft
    }

    // MARK: Più letture dello stesso documento

    /// Unisce le letture dello stesso documento, giorno per giorno.
    ///
    /// L'OCR non è stabile: sugli screenshot dell'app di Explora ogni impostazione
    /// perdeva righe diverse — una «Puerto Plata», un'altra «Partenza: 17:00» e «In
    /// mare». Scegliere la lettura migliore lasciava comunque un buco; unirle no. Per
    /// ogni data si tiene la tappa più completa col porto più visto, e i buchi si
    /// riempiono con quello che hanno letto le altre. Un porto con i suoi orari vince su
    /// «in mare» nella stessa data: l'OCR può perdere righe, non inventarle.
    func combine(_ drafts: [ItineraryDraft]) -> ItineraryDraft {
        guard drafts.count > 1 else { return drafts.first ?? ItineraryDraft() }

        struct Day: Hashable, Comparable {
            let year: Int, month: Int, day: Int
            static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
        }
        let sanityIssues: Set<DraftIssue> = [.implausibleLeg, .timesOutOfOrder, .dateOutOfOrder]
        var byDay: [Day: [DraftCall]] = [:]
        for draft in drafts {
            for var call in draft.calls {
                guard let day = call.day, let month = call.month, let year = call.year else { continue }
                // Gli all aboard dedotti e i controlli si rifanno dopo, sull'unione.
                if call.issues.contains(.allAboardAssumed) {
                    call.allAboard = nil
                    call.issues.remove(.allAboardAssumed)
                }
                call.issues.subtract(sanityIssues)
                byDay[Day(year: year, month: month, day: day), default: []].append(call)
            }
        }

        func completeness(_ call: DraftCall) -> Int {
            (call.portCandidates.isEmpty ? 0 : 3) + (call.arrival == nil ? 0 : 1)
                + (call.departure == nil ? 0 : 1) + (call.allAboard == nil ? 0 : 1)
                - (call.isBlocked ? 4 : 0)
        }

        var calls: [DraftCall] = []
        for day in byDay.keys.sorted() {
            let group = byDay[day]!
            let withPort = group.filter { !$0.isSeaDay && !$0.portCandidates.isEmpty }
            guard !withPort.isEmpty else {
                if let sea = group.first(where: \.isSeaDay) {
                    calls.append(sea)
                } else if let best = group.max(by: { completeness($0) < completeness($1) }) {
                    calls.append(best)
                }
                continue
            }
            // Il porto letto più volte; a parità, quello della tappa più completa.
            let votes = Dictionary(grouping: withPort, by: { $0.portCandidates[0].name })
            let port = votes.max { a, b in
                a.value.count != b.value.count ? a.value.count < b.value.count
                    : completeness(a.value.max { completeness($0) < completeness($1) }!)
                        < completeness(b.value.max { completeness($0) < completeness($1) }!)
            }!.key
            let same = withPort.filter { $0.portCandidates[0].name == port }
            var chosen = same.max { completeness($0) < completeness($1) }!
            // Gli orari si prendono dalle letture dello stesso porto e da quelle della
            // stessa data che il porto non l'hanno visto.
            for other in group where !other.isSeaDay && other.id != chosen.id
                && (other.portCandidates.isEmpty || other.portCandidates[0].name == port) {
                chosen.arrival = chosen.arrival ?? other.arrival
                chosen.departure = chosen.departure ?? other.departure
                chosen.allAboard = chosen.allAboard ?? other.allAboard
                if other.berth == .tender { chosen.berth = .tender }
            }
            if chosen.arrival != nil { chosen.issues.remove(.missingTimes) }
            calls.append(chosen)
        }

        var combined = ItineraryDraft()
        let names = drafts.compactMap(\.shipName)
        combined.shipName = Dictionary(grouping: names, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        combined.statedNights = drafts.lazy.compactMap(\.statedNights).first
        combined.statedPorts = drafts.lazy.compactMap(\.statedPorts).first
        combined.calls = calls
        fillAssumedAllAboard(&combined.calls)
        ItinerarySanityCheck.run(&combined)
        return combined
    }

    /// «7 notti · 7 porti», come lo scrivono le compagnie in testa all'itinerario.
    ///
    /// Explora lo scrive a lettere spaziate («7 N OTT I 7 P O R T I»): le righe fatte
    /// quasi solo di lettere singole si ricompongono togliendo gli spazi.
    static func statedCounts(in lines: [String]) -> (nights: Int?, ports: Int?) {
        var nights: Int?, ports: Int?
        for line in lines {
            let tokens = line.split(separator: " ")
            let spaced = tokens.count >= 6 && tokens.filter({ $0.count <= 2 }).count * 3 >= tokens.count * 2
            let text = (spaced ? tokens.joined() : line).lowercased()
            let pattern = spaced ? #/(\d{1,2})(notti|nights|porti|ports)/# : #/\b(\d{1,2})\s+(notti|nights|porti|ports|scali)\b/#
            for match in text.matches(of: pattern) {
                guard let value = Int(match.1) else { continue }
                if match.2 == "notti" || match.2 == "nights" { nights = nights ?? value } else { ports = ports ?? value }
            }
        }
        return (nights, ports)
    }

    // MARK: Righe da scartare

    /// Piè di pagina, contatti e barre di stato: righe che non appartengono a
    /// nessuna tappa, ma che finivano dentro quella in cui cadevano.
    static func isBoilerplate(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.firstMatch(of: #/^(?:page|pagina|pag\.)\s*\d+\s*(?:di|of|/)\s*\d+/#) != nil { return true }
        if lowered.contains("@") || lowered.contains("www.") || lowered.contains("http") { return true }
        // La barra di stato di uno screenshot, «12:48 1 63»: un orario seguito solo da
        // numerini. Letta come orario, dava a una tappa l'ora in cui era stata fatta
        // la foto.
        if lowered.firstMatch(of: #/^\d{1,2}:\d{2}(?:\s+\S{1,3})+$/#) != nil,
           !lowered.contains(where: \.isLetter) { return true }
        return false
    }

    /// Un paragrafo descrittivo. Chiude la tappa in cui cade: i nomi di luogo della
    /// prosa («passeggia a Frederiksted e a Christiansted») non devono diventare porti.
    private static func isProse(_ line: String) -> Bool {
        line.split(separator: " ").count >= 14
            && line.firstMatch(of: #/\d{1,2}[:.h]\d{2}/#) == nil
    }

    /// «Giorno 3: Saint John's», «Day 7 — At sea».
    private static func dayHeading(_ line: String) -> Int? {
        guard let m = line.lowercased().firstMatch(of: #/^\s*(?:giorno|day)\s+(\d{1,2})\b/#) else { return nil }
        return Int(m.1)
    }

    /// Una riga che dice solo «In mare», «Day at sea».
    private static func isSeaDayLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return line.split(separator: " ").count <= 5 && seaDayWords.contains { lowered.contains($0) }
    }

    // MARK: Nome della nave

    private func shipName(in lines: [String]) -> String? {
        // «La nave» da sola su una riga, e sotto il nome: è così che Explora la scrive
        // a pagina quattro. Non si può contare sull'elenco per trovarla: Explora III
        // è stata varata dopo la fotografia di Wikidata, e il test passava solo
        // perché un altro test l'aveva insegnata al simulatore. Viene prima
        // dell'elenco perché qui è il documento a dire quale riga è la nave, mentre
        // l'elenco, provato su ogni riga, scambierebbe il porto di Hamburg per la
        // nave Hamburg.
        for (heading, name) in zip(lines, lines.dropFirst()) where Self.isShipHeading(heading) {
            guard (3...40).contains(name.count), name.split(separator: " ").count <= 4,
                  name.contains(where: \.isLetter) else { continue }
            return ShipDirectory.shared.lookup(name)?.name ?? Self.shipCased(name)
        }
        // Una riga che è il nome di una nave dell'elenco vince sul resto, ovunque stia:
        // in copertina c'è il titolo del viaggio, non la nave.
        for line in lines where line.count <= 40 {
            if let record = ShipDirectory.shared.lookup(line) { return record.name }
        }
        for line in lines.prefix(6) {
            let lowered = line.lowercased()
            if let range = lowered.range(of: #"(?:nave|ship|m/?[nsv])[:\s]+"#,
                                         options: .regularExpression) {
                let name = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        // Nessuna etichetta: la prima riga breve senza cifre è il candidato migliore.
        // Al massimo quattro parole: un nome di nave è corto, e il titolo di un
        // viaggio («Un viaggio per rifugiarsi in…») non deve passare per una nave.
        for line in lines.prefix(3) where !line.contains(where: \.isNumber) {
            if line.count <= 40, line.count >= 3, line.split(separator: " ").count <= 4 { return line }
        }
        return nil
    }

    /// «La nave», «The ship:» — un titoletto, non una frase che parla della nave.
    private static func isShipHeading(_ line: String) -> Bool {
        let heading = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        return ["nave", "la nave", "la tua nave", "la vostra nave",
                "ship", "the ship", "your ship"].contains(heading)
    }

    /// «EXPLORA III» → «Explora III». Le brochure scrivono il nome in maiuscolo come
    /// un titolo: quando l'elenco lo conosce lo riscrive lui, ma una nave che non
    /// conosce resterebbe urlata nel riesame. I numeri romani restano maiuscoli.
    private static func shipCased(_ name: String) -> String {
        guard name == name.uppercased() else { return name }
        return name.split(separator: " ").map { word in
            if word.allSatisfy({ "IVX".contains($0) }) { return String(word) }
            return word.prefix(1) + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    // MARK: Blocchi

    private struct Block {
        var lines: [String]
        /// Nulla per un giorno scritto senza data («Giorno 7: In mare»): la data si
        /// ricava dopo, dal numero del giorno o dalle tappe vicine.
        var date: FoundDate?
        /// La riga in cui stava la data, e dove va tolta prima di cercare il porto.
        var dateLineIndex: Int?
        var dayNumber: Int?
        /// Chiuso da un paragrafo di prosa: non assorbe più niente.
        var closed = false
    }

    /// Divide il testo in tappe.
    ///
    /// Una tappa comincia con una data, oppure con un titolo «Giorno N»: Explora
    /// scrive il porto **nel titolo, sopra la data** («Giorno 2: Nuovi orizzonti ad
    /// Anguilla», poi «lun 16 nov · Imbarco 09:00»), e leggendo solo dalla data in giù
    /// il porto finiva nella tappa di prima.
    private func blocks(from lines: [String], order: NumericOrder) -> [Block] {
        var blocks: [Block] = []
        for line in lines {
            if let number = Self.dayHeading(line) {
                let date = findDate(in: line, order: order)
                blocks.append(Block(lines: [line], date: date,
                                    dateLineIndex: date == nil ? nil : 0, dayNumber: number))
                continue
            }

            // «15 novembre 2026 - 22 novembre 2026»: la durata del viaggio, non una tappa.
            if let date = findDate(in: line, order: order), !isDateRange(line, first: date, order: order) {
                if var last = blocks.last, last.date == nil, last.dayNumber != nil,
                   !last.closed, last.lines.count <= 2 {
                    // La data subito sotto un titolo «Giorno N» è la sua.
                    last.date = date
                    last.dateLineIndex = last.lines.count
                    last.lines.append(line)
                    blocks[blocks.count - 1] = last
                } else {
                    blocks.append(Block(lines: [line], date: date, dateLineIndex: 0))
                }
                continue
            }

            guard var last = blocks.last, !last.closed,
                  last.lines.count < Self.maximumBlockLines else { continue }
            if Self.isProse(line) {
                last.closed = true
            } else if Self.isSeaDayLine(line), last.lines.contains(where: { $0.firstMatch(of: #/\d{1,2}[:.h]\d{2}/#) != nil }) {
                // «In mare» dopo una tappa che ha già i suoi orari è il giorno dopo, con
                // la data persa: capita negli screenshot, quando l'OCR storpia «Sab 21
                // Nov». Senza, Puerto Plata diventava un giorno di mare.
                blocks.append(Block(lines: [line], date: nil, dateLineIndex: nil))
                continue
            } else {
                last.lines.append(line)
            }
            blocks[blocks.count - 1] = last
        }
        return blocks
    }

    /// Una riga con due date è un intervallo.
    private func isDateRange(_ line: String, first: FoundDate, order: NumericOrder) -> Bool {
        guard first.range.upperBound <= line.endIndex else { return false }
        return findDate(in: String(line[first.range.upperBound...]), order: order) != nil
    }

    // MARK: Una tappa

    private func call(from block: Block, order: NumericOrder) -> DraftCall? {
        let joined = block.lines.joined(separator: " ")
        let lowered = joined.lowercased()

        var call = DraftCall(rawName: "", sourceLine: joined)
        call.day = block.date?.day
        call.month = block.date?.month
        call.year = block.date?.year
        call.dayNumber = block.dayNumber
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

        // Gli orari si raccolgono da tutto il blocco, nell'ordine in cui compaiono,
        // ciascuno con l'etichetta che lo precede se ce l'ha.
        var schedule: [TimeOfDay] = []
        var labelledArrival: TimeOfDay?
        var labelledDeparture: TimeOfDay?
        var residues: [String] = []
        for (index, line) in block.lines.enumerated() {
            var consumed: [Range<String.Index>] = []
            if index == block.dateLineIndex, let date = block.date { consumed.append(date.range) }
            if let aboardRange = consumedByAboard[index] { consumed.append(aboardRange) }

            let lowered = line.lowercased()
            let found = times(in: lowered, excluding: consumed)
            var previousEnd = lowered.startIndex
            for time in found {
                switch label(before: time.range, in: lowered, since: previousEnd) {
                case .arrival: labelledArrival = labelledArrival ?? time.time
                case .departure: labelledDeparture = labelledDeparture ?? time.time
                case nil: break
                }
                previousEnd = time.range.upperBound
            }
            schedule.append(contentsOf: found.map(\.time))
            consumed.append(contentsOf: found.map(\.range))
            residues.append(residue(of: line, removing: consumed))
        }

        if labelledArrival != nil || labelledDeparture != nil {
            // Con le etichette si crede alle etichette, e gli orari senza etichetta si
            // ignorano: negli screenshot dell'app di Explora sono gli orari della cena
            // («Fil Rouge · Deck 4 · 20:00 - 22:00»), non della nave.
            call.arrival = labelledArrival
            call.departure = labelledDeparture
        } else {
            if let first = schedule.first { call.arrival = first }
            if schedule.count > 1 { call.departure = schedule[1] }
        }

        if call.isSeaDay { return call }

        // Il nome del porto è il residuo che si aggancia meglio all'elenco: così una
        // riga come "Cabina 11024 · ponte 11", assorbita nel blocco, non può vincere
        // contro quella che contiene davvero il porto.
        var best: (name: String, candidates: [PortMatch])?
        for residue in residues where residue.count >= 3 {
            var candidates = PortGazetteer.shared.candidates(residue)
            // Se il residuo intero non si aggancia bene, il porto può stare dentro una
            // frase: «Rullo di tamburi per Puerto Plata».
            if (candidates.first?.confidence ?? 0) < 0.8 {
                let inside = portInside(residue)
                if !inside.isEmpty { candidates = inside }
            }
            // Ultimo tentativo: il nome storpiato dall'OCR, intero o un pezzo alla volta.
            if candidates.isEmpty {
                for piece in [residue] + residue.split(whereSeparator: { ",()".contains($0) }).map(String.init) {
                    candidates = PortGazetteer.shared.fuzzyCandidates(piece)
                    if !candidates.isEmpty { break }
                }
            }
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

        // Senza orari, o con la sola partenza: il riesame lo dice invece di lasciare
        // che l'arrivo diventi la mezzanotte in silenzio.
        if schedule.isEmpty || (call.arrival == nil && call.departure != nil) {
            call.issues.insert(.missingTimes)
        }

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

    private enum Slot { case arrival, departure }

    /// L'etichetta più vicina prima di un orario, cercata solo fra l'orario precedente
    /// e questo: in «Imbarco 09:00 · Partenza 19:00» la partenza non deve vedere
    /// l'imbarco.
    private func label(before range: Range<String.Index>, in text: String,
                       since start: String.Index) -> Slot? {
        let window = text[start..<range.lowerBound].suffix(24)
        var best: (slot: Slot, end: String.Index)?
        for (slot, labels) in [(Slot.arrival, Self.arrivalLabels), (.departure, Self.departureLabels)] {
            for label in labels {
                guard let found = window.range(of: label, options: .backwards) else { continue }
                if best == nil || found.upperBound > best!.end { best = (slot, found.upperBound) }
            }
        }
        if let best { return best.slot }

        // Un'etichetta storpiata dall'OCR, «Parenza: 17.00»: si accetta a una lettera
        // di distanza, solo per le etichette lunghe, dove una lettera non cambia parola.
        let words = window.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for word in words.reversed() where word.count >= 6 {
            for (slot, labels) in [(Slot.arrival, Self.arrivalLabels), (.departure, Self.departureLabels)] {
                if labels.contains(where: { $0.count >= 6 && EditDistance.between(word, $0, limit: 1) <= 1 }) {
                    return slot
                }
            }
        }
        return nil
    }

    // MARK: Porto dentro una frase

    /// Cerca un porto fra le parole di una frase: le più lunghe prima, e solo con
    /// corrispondenze esatte, perché un ripiego largo troverebbe un porto in ogni parola.
    ///
    /// Le elisioni si staccano prima («dell'Isola Catalina» → «isola catalina»), e
    /// «Isola X» si prova anche come «X Island»: senza, restava «Catalina» da sola, che
    /// nell'elenco è un porto in Canada.
    private func portInside(_ text: String) -> [PortMatch] {
        let elisions: Set<String> = ["l", "d", "dell", "dall", "nell", "sull", "all", "un", "c", "s", "quest"]
        var words: [String] = []
        for raw in text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "(" || $0 == ")" }) {
            var token = String(raw)
            if let apostrophe = token.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }) {
                let head = PortGazetteer.fold(String(token[..<apostrophe]))
                if elisions.contains(head) { token = String(token[token.index(after: apostrophe)...]) }
            }
            let folded = PortGazetteer.fold(token)
            if !folded.isEmpty { words.append(contentsOf: folded.split(separator: " ").map(String.init)) }
        }
        guard !words.isEmpty else { return [] }

        let gazetteer = PortGazetteer.shared
        for length in stride(from: min(4, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let window = Array(words[start..<start + length])
                guard !window.allSatisfy(Self.windowStopwords.contains) else { continue }
                if length == 1, window[0].count < 4 || Self.windowStopwords.contains(window[0]) { continue }
                let key = window.joined(separator: " ")

                var found: [PortMatch] = []
                if let alias = Self.portAliases[key] { found = gazetteer.exactCandidates(alias) }
                if found.isEmpty, length >= 2, ["isola", "isla", "ile", "island"].contains(window[0]) {
                    found = gazetteer.exactCandidates(window.dropFirst().joined(separator: " ") + " island")
                }
                if found.isEmpty { found = gazetteer.exactCandidates(key) }
                if !found.isEmpty {
                    return found.map { var m = $0; m.confidence = 0.8; return m }
                }
            }
        }
        return []
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

    /// Fonde le tappe ripetute.
    ///
    /// Chi manda tre screenshot consecutivi li manda sovrapposti: «Mar 17 Nov ·
    /// Saint John's» compare in fondo al primo e in cima al secondo. Due tappe con la
    /// stessa data si fondono se non si contraddicono — stesso porto, o una delle due
    /// senza porto — tenendo di ciascuna quello che l'altra non ha.
    private func mergingDuplicates(_ calls: [DraftCall]) -> [DraftCall] {
        var result: [DraftCall] = []
        for call in calls {
            guard let day = call.day, let index = result.lastIndex(where: {
                $0.day == day && $0.month == call.month && $0.isSeaDay == call.isSeaDay
            }) else { result.append(call); continue }
            var kept = result[index]
            let samePort = kept.portCandidates.first?.name == call.portCandidates.first?.name
                || kept.portCandidates.isEmpty || call.portCandidates.isEmpty
            guard samePort else { result.append(call); continue }
            if kept.portCandidates.isEmpty, !call.portCandidates.isEmpty {
                kept.rawName = call.rawName
                kept.port = call.port
                kept.portCandidates = call.portCandidates
                kept.issues.remove(.portUnknown)
                if call.issues.contains(.portUncertain) { kept.issues.insert(.portUncertain) }
            }
            kept.arrival = kept.arrival ?? call.arrival
            kept.departure = kept.departure ?? call.departure
            kept.allAboard = kept.allAboard ?? call.allAboard
            if call.berth == .tender { kept.berth = .tender }
            if kept.arrival != nil || kept.departure != nil,
               !(kept.arrival == nil && kept.departure != nil) {
                kept.issues.remove(.missingTimes)
            }
            kept.dayNumber = kept.dayNumber ?? call.dayNumber
            result[index] = kept
        }
        return result
    }

    /// Data una tappa con numero di giorno e data, data anche quelle che hanno solo il
    /// numero: «Giorno 7: In mare» è il giorno 1 più sei.
    private func fillDatesFromDayNumbers(_ calls: inout [DraftCall], documentYear: Int?) {
        guard let reference = calls.first(where: { $0.dayNumber != nil && $0.day != nil && $0.month != nil }),
              let referenceDate = date(of: reference, documentYear: documentYear) else { return }
        let calendar = Calendar(identifier: .gregorian)
        for index in calls.indices where calls[index].day == nil {
            guard let number = calls[index].dayNumber,
                  let date = calendar.date(byAdding: .day, value: number - reference.dayNumber!, to: referenceDate)
            else { continue }
            set(&calls[index], to: date, knownYear: reference.year)
        }
    }

    /// Una tappa senza data fra due che ce l'hanno, con un giorno libero in mezzo,
    /// è quel giorno: succede quando l'OCR storpia la data di un giorno di mare.
    private func fillDatesBetweenNeighbours(_ calls: inout [DraftCall], documentYear: Int?) {
        let calendar = Calendar(identifier: .gregorian)
        for index in calls.indices where calls[index].day == nil {
            guard index > 0, index < calls.count - 1,
                  let previous = date(of: calls[index - 1], documentYear: documentYear),
                  let next = date(of: calls[index + 1], documentYear: documentYear),
                  let gap = calendar.dateComponents([.day], from: previous, to: next).day, gap == 2,
                  let date = calendar.date(byAdding: .day, value: 1, to: previous) else { continue }
            set(&calls[index], to: date, knownYear: calls[index - 1].year)
        }
    }

    /// La data di una tappa, per fare i conti fra tappe. L'anno è quello scritto, poi
    /// quello del documento, poi l'anno in corso: qui serve solo a contare i giorni.
    private func date(of call: DraftCall, documentYear: Int?) -> Date? {
        guard let day = call.day, let month = call.month else { return nil }
        let year = call.year ?? documentYear ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))
    }

    private func set(_ call: inout DraftCall, to date: Date, knownYear: Int?) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        call.day = parts.day
        call.month = parts.month
        // L'anno solo se era scritto: altrimenti lo decide `resolveYears`, che guarda
        // tutta la crociera.
        if knownYear != nil { call.year = parts.year }
    }

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
    private func resolveYears(_ calls: inout [DraftCall], documentYear: Int?) {
        guard !calls.isEmpty else { return }
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let thisYear = calendar.component(.year, from: today)

        var year = calls.compactMap(\.year).first ?? documentYear ?? {
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
