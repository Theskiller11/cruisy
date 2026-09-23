import Foundation

/// Un orario del giorno, in minuti dalla mezzanotte.
struct TimeOfDay: Equatable, Hashable, Sendable, Comparable {
    var minutes: Int

    init(minutes: Int) { self.minutes = max(0, min(minutes, 24 * 60 - 1)) }
    init(hour: Int, minute: Int) { self.init(minutes: hour * 60 + minute) }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }
    var formatted: String { String(format: "%02d:%02d", hour, minute) }

    static func < (a: TimeOfDay, b: TimeOfDay) -> Bool { a.minutes < b.minutes }

    func offset(byMinutes delta: Int) -> TimeOfDay { TimeOfDay(minutes: minutes + delta) }

    /// Legge un orario scritto a mano: "9:30", "09.30", "9:30 PM", "0930".
    /// Torna nullo su tutto il resto, invece di indovinare.
    init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        var hour: Int
        var minute: Int
        var meridiem: String?

        if let m = trimmed.firstMatch(of: #/(\d{1,2})[:.h](\d{2})\s*(am|pm)?/#) {
            hour = Int(m.1) ?? -1
            minute = Int(m.2) ?? -1
            meridiem = m.3.map(String.init)
        } else if let m = trimmed.firstMatch(of: #/^(\d{2})(\d{2})$/#) {
            // "0930", come lo si scrive di fretta.
            hour = Int(m.1) ?? -1
            minute = Int(m.2) ?? -1
        } else {
            return nil
        }

        guard minute >= 0, minute < 60 else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm" && hour != 12 { hour += 12 }
            if meridiem == "am" && hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour) else { return nil }
        self.init(hour: hour, minute: minute)
    }
}

/// Cosa non torna in una riga letta.
///
/// Il bozzetto non nasconde mai i dubbi: ogni cosa dedotta o non trovata si porta
/// dietro il suo segnale, e il riesame li mette in cima. Un'app che può farti perdere
/// la nave non deve far sembrare certo quello che ha indovinato.
enum DraftIssue: String, Hashable, Sendable, CaseIterable {
    case portUnknown
    case portUncertain
    case missingDate
    case missingTimes
    case allAboardAssumed
    /// Per arrivarci dal porto prima la nave dovrebbe andare più veloce di quanto
    /// una nave da crociera possa: quasi sempre è il porto a essere sbagliato.
    case implausibleLeg
    case timesOutOfOrder
    case dateOutOfOrder

    var label: String {
        switch self {
        case .portUnknown: String(localized: "Porto non riconosciuto")
        case .portUncertain: String(localized: "Porto da confermare")
        case .missingDate: String(localized: "Data mancante")
        case .missingTimes: String(localized: "Orari mancanti")
        case .allAboardAssumed: String(localized: "All aboard dedotto")
        case .implausibleLeg: String(localized: "Troppo lontano dal porto prima: controlla il porto")
        case .timesOutOfOrder: String(localized: "Orari che non tornano")
        case .dateOutOfOrder: String(localized: "Data fuori ordine")
        }
    }

    /// Se blocca la conferma o si limita ad avvisare.
    ///
    /// I controlli di buon senso avvisano e basta: dicono che qualcosa è strano, non
    /// che è sbagliato, e l'ultima parola resta a chi ha il programma di bordo in mano.
    var isBlocking: Bool {
        switch self {
        case .portUnknown, .missingDate: true
        case .portUncertain, .missingTimes, .allAboardAssumed,
             .implausibleLeg, .timesOutOfOrder, .dateOutOfOrder: false
        }
    }
}

/// Uno scalo letto da un testo, prima che diventi un `PortCall`.
struct DraftCall: Identifiable, Sendable {
    let id = UUID()
    /// Il nome come stava scritto nel documento.
    var rawName: String
    var port: PortMatch?
    /// Tutti i porti che quel nome potrebbe indicare. Più di uno significa che il
    /// nome è ambiguo e qualcuno deve scegliere — la geografia della crociera o
    /// una persona, mai il caso.
    var portCandidates: [PortMatch] = []
    /// Giorno e mese; l'anno si decide dopo, guardando tutta la crociera.
    var day: Int?
    var month: Int?
    var year: Int?
    var arrival: TimeOfDay?
    var departure: TimeOfDay?
    var allAboard: TimeOfDay?
    var berth: Berth.Kind = .dock
    var isSeaDay = false
    /// Il numero del giorno di crociera, quando il documento lo scrive («Giorno 7»).
    /// Serve a datare le tappe che una data non ce l'hanno, tipicamente i giorni di mare.
    var dayNumber: Int?
    /// La riga da cui viene, mostrata nel riesame per poter confrontare con l'originale.
    var sourceLine: String = ""
    var issues: Set<DraftIssue> = []

    init(rawName: String, port: PortMatch? = nil, portCandidates: [PortMatch] = [],
         day: Int? = nil, month: Int? = nil, year: Int? = nil,
         arrival: TimeOfDay? = nil, departure: TimeOfDay? = nil, allAboard: TimeOfDay? = nil,
         berth: Berth.Kind = .dock, isSeaDay: Bool = false,
         sourceLine: String = "", issues: Set<DraftIssue> = []) {
        self.rawName = rawName
        self.port = port
        self.portCandidates = portCandidates
        self.day = day; self.month = month; self.year = year
        self.arrival = arrival; self.departure = departure; self.allAboard = allAboard
        self.berth = berth; self.isSeaDay = isSeaDay
        self.sourceLine = sourceLine; self.issues = issues
    }

    var displayName: String {
        if isSeaDay { return String(localized: "Giorno di mare") }
        return port?.name ?? rawName
    }

    var isBlocked: Bool { issues.contains(where: \.isBlocking) }
}

/// Il risultato della lettura, prima della conferma.
struct ItineraryDraft: Sendable {
    var shipName: String?
    var calls: [DraftCall] = []
    /// Da dove è arrivato il testo, per dirlo nel riesame.
    var source: Source = .pastedText
    /// Quello che il documento dice di sé in testa — «7 notti · 7 porti» — per
    /// accorgersi di una tappa persa.
    var statedNights: Int?
    var statedPorts: Int?
    /// Avvisi sull'itinerario intero, mostrati in cima al riesame.
    var warnings: [String] = []

    enum Source: Sendable {
        case pastedText, scannedDocument, pdf, images

        var label: String {
            switch self {
            case .pastedText: String(localized: "testo incollato")
            case .scannedDocument: String(localized: "documento scansionato")
            case .pdf: String(localized: "PDF")
            case .images: String(localized: "foto e screenshot")
            }
        }
    }

    var isEmpty: Bool { calls.isEmpty }

    /// Quanto è buona una lettura, per scegliere fra due letture dello stesso documento.
    ///
    /// Conta quello che serve davvero: porti agganciati, orari trovati, giorni di mare
    /// riconosciuti; toglie per ogni riga che blocca la conferma. Non misura se è
    /// **giusta** — quello lo fa il riesame — ma fra due letture tiene quella che ha
    /// capito di più.
    var quality: Int {
        calls.reduce(0) { score, call in
            var value = score
            if call.isSeaDay { value += 2 }
            if !call.portCandidates.isEmpty { value += 3 }
            if call.arrival != nil { value += 1 }
            if call.departure != nil { value += 1 }
            if call.day != nil, call.month != nil { value += 1 }
            if call.isBlocked { value -= 4 }
            return value - call.issues.filter { !$0.isBlocking }.count / 2
        }
    }
    var hasBlockingIssues: Bool { calls.contains { $0.isBlocked } }

    /// Gli scali veri, senza i giorni di mare (che l'app ricava da sola).
    var portCalls: [DraftCall] { calls.filter { !$0.isSeaDay } }

    /// Trasforma il bozzetto in una crociera.
    ///
    /// I giorni di mare vengono **scartati**: nel modello non sono righe salvate ma si
    /// ricavano dai buchi fra uno scalo e il successivo. Tenerli sarebbe un secondo
    /// posto in cui la stessa verità può andare fuori sincrono.
    func voyage(clock: ShipClock, existingID: UUID? = nil) -> Voyage? {
        let usable = portCalls.filter { !$0.isBlocked }
        guard usable.count >= 2, let shipName, !shipName.isEmpty else { return nil }

        var calls: [PortCall] = []
        for (index, draft) in usable.enumerated() {
            guard let day = draft.day, let month = draft.month, let port = draft.port
            else { continue }

            // **Gli orari di un itinerario sono ora locale del porto**, non ora di
            // bordo: sono quelli stampati dalla compagnia, e la compagnia li scrive
            // nell'ora del posto dove attracchi. Ancorarli tutti a un unico fuso —
            // com'era prima — spostava di ore ogni scalo in un fuso diverso da
            // quello d'imbarco, e l'errore cresceva man mano che la crociera
            // avanzava, cioè proprio dove serve fidarsi.
            let zone = port.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                ?? TimeZone(secondsFromGMT: ShipClock.nauticalOffset(
                    longitude: port.coordinate.longitude))
                ?? clock.timeZone(at: .now)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone

            guard let midnight = calendar.date(from: DateComponents(
                year: draft.year, month: month, day: day)) else { continue }

            func instant(_ time: TimeOfDay?) -> Date? {
                time.map { midnight.addingTimeInterval(Double($0.minutes) * 60) }
            }

            let isLast = index == usable.count - 1
            calls.append(PortCall(
                name: port.name,
                region: port.country,
                coordinate: port.coordinate,
                timeZoneIdentifier: port.timeZoneIdentifier,
                role: index == 0 ? .embarkation : isLast ? .disembarkation : .port,
                arrival: instant(draft.arrival) ?? midnight,
                departure: isLast ? nil : instant(draft.departure),
                allAboard: isLast ? nil : instant(draft.allAboard),
                berth: Berth(kind: draft.berth),
                // Viene da un documento letto dall'app, non da un orario che
                // l'utente ha digitato guardandolo: resta "orario pubblicato".
                scheduleOrigin: .publishedSchedule))
        }

        guard calls.count >= 2 else { return nil }
        let voyage = Voyage(id: existingID ?? UUID(), shipName: shipName,
                            clock: clock, calls: calls)
        // L'orologio si ricava dagli scali: in porto l'ora del porto, in traversata
        // il cambio delle 02:00. `clock` resta solo come ripiego e per il caso in cui
        // l'abbia impostato a mano chi è a bordo.
        return voyage.withScheduledClock()
    }
}
