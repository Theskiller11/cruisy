import SwiftUI

/// Il biglietto di oggi: l'ora stampata grande, e sotto la matrice con il countdown
/// e i campi.
///
/// Ogni scalo è una carta d'imbarco. In porto la cosa più grande è **l'ora del
/// rientro a bordo**, come su un biglietto: si ricorda un'ora, non dei secondi, e il
/// countdown ne è la conseguenza. In mare il biglietto è verso il prossimo scalo, e
/// l'ora grande è quella dell'arrivo. Prima dell'imbarco è l'ora dell'imbarco.
///
/// L'orario pubblicato fa fede: il countdown viene dall'itinerario, e il campo
/// «Orario» dice sempre da dove viene.
struct BoardingPass: View {
    @Environment(\.livery) private var livery
    let voyage: Voyage
    let moment: Voyage.Moment
    let focus: Voyage.Focus?
    let now: Date
    var offset: TimeInterval = 0
    var fix: ShipFix?
    var speedUnit: SpeedUnit = .knots

    private var clock: ShipClock { voyage.clock }

    var body: some View {
        Ticket {
            top
        } stub: {
            stub
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: La parte alta

    @ViewBuilder
    private var top: some View {
        TicketHead(eyebrow: eyebrow, place: place, stamp: stamp) { hour }
    }

    @ViewBuilder
    private var hour: some View {
        switch layout {
        case .daysAway(let days):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(days)")
                    .ticketNumeral(size: 76, cap: 104)
                    .foregroundStyle(livery.ink)
                Text(days == 1 ? "giorno" : "giorni")
                    .font(TicketType.place)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.field)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(days == 1 ? "Manca un giorno all'imbarco"
                                     : "Mancano \(days) giorni all'imbarco"))
        case .completed:
            Text(voyage.nights == 1 ? "1 notte" : "\(voyage.nights) notti")
                .ticketNumeral(size: 60, cap: 84)
                .foregroundStyle(livery.ink)
        case .hour(let date):
            Text(clock.time(date))
                .ticketHour()
                .foregroundStyle(livery.ink)
                .accessibilityLabel(Text("\(eyebrow) alle \(clock.time(date))"))
        }
    }

    // MARK: La matrice

    @ViewBuilder
    private var stub: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let focus, let countdownLabel {
                TicketCountRow(label: countdownLabel) {
                    CountdownView(countdown: focus.countdown, offset: offset)
                }
                TicketRule()
            }
            TicketMatrix(fields: fields)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    // MARK: Che biglietto è

    private enum HourLayout {
        case hour(Date)
        case daysAway(Int)
        case completed
    }

    /// Giorni di bordo che restano all'imbarco: la differenza fra le due mezzanotti,
    /// non le ore divise per 24. È così che una persona li conta.
    private func daysAway(to target: Date) -> Int {
        let today = clock.startOfDay(for: now)
        let boarding = clock.startOfDay(for: target)
        return max(0, Int((boarding.timeIntervalSince(today) / 86_400).rounded()))
    }

    /// Sotto le trentasei ore si passa all'ora precisa; sopra, si conta in giorni.
    private static let precisionThreshold: TimeInterval = 36 * 3600

    private var layout: HourLayout {
        switch (moment, focus?.kind) {
        case (.beforeVoyage(let call), _):
            let target = call.allAboard ?? call.arrival
            if target.timeIntervalSince(now) > Self.precisionThreshold {
                return .daysAway(daysAway(to: target))
            }
            return .hour(target)
        case (.inPort(let call), .some(.allAboard)):
            return .hour(call.allAboard ?? call.castOff)
        case (.inPort(let call), _):
            return .hour(call.castOff)
        case (.atSea(_, let to), _):
            return .hour(to.arrival)
        case (.completed, _):
            return .completed
        }
    }

    private var eyebrow: String {
        switch (moment, focus?.kind) {
        case (.beforeVoyage, _): String(localized: "Imbarco")
        case (.inPort, .some(.allAboard)): String(localized: "Rientro a bordo")
        case (.inPort, _): String(localized: "Partenza")
        case (.atSea, _): String(localized: "Arrivo")
        case (.completed, _): String(localized: "Crociera conclusa")
        }
    }

    private var place: String {
        switch moment {
        case .beforeVoyage(let call):
            let date = Format.dayMonth(call.arrival, clock: clock)
            return "\(call.name) · \(date)"
        case .inPort(let call):
            return [call.name, call.berth.name].compactMap(\.self).joined(separator: " · ")
        case .atSea(_, let to):
            return [to.name, to.region].filter { !$0.isEmpty }.joined(separator: " · ")
        case .completed:
            return [voyage.calls.first?.name, voyage.calls.last?.name].compactMap(\.self).joined(separator: " → ")
        }
    }

    private var stamp: String {
        switch (moment, focus?.kind) {
        case (.beforeVoyage, _): String(localized: "A\nterra", comment: "Timbro")
        case (.inPort(let call), .some(.allAboard)):
            call.berth.kind == .tender ? String(localized: "Tender", comment: "Timbro")
                                       : String(localized: "In\nporto", comment: "Timbro")
        case (.inPort, _): String(localized: "A\nbordo", comment: "Timbro")
        case (.atSea, _): String(localized: "In\nmare", comment: "Timbro")
        case (.completed, _): String(localized: "Sbarcati", comment: "Timbro")
        }
    }

    private var countdownLabel: String? {
        switch (moment, focus?.kind) {
        case (.beforeVoyage, _):
            if case .daysAway = layout { return nil }
            return String(localized: "Mancano")
        case (.inPort, .some(.allAboard)): return String(localized: "Mancano")
        case (.inPort, .some(.sailAway)): return String(localized: "Si salpa fra")
        case (.atSea, _): return String(localized: "Mancano")
        default: return nil
        }
    }

    /// I campi della matrice, nell'ordine in cui si leggono.
    private var fields: [TicketField] {
        var fields: [TicketField] = []
        switch moment {
        case .beforeVoyage(let call):
            fields.append(TicketField(label: String(localized: "Nave"), value: voyage.shipName))
            if let last = voyage.calls.last {
                fields.append(TicketField(label: String(localized: "Sbarco"), value: last.name))
            }
            fields.append(TicketField(label: String(localized: "Notti"), value: "\(voyage.nights)"))
            fields.append(TicketField(label: String(localized: "Scali"), value: "\(voyage.intermediateCalls.count)"))
            if let boarding = call.allAboard, call.arrival != boarding {
                fields.append(TicketField(label: String(localized: "Imbarco dalle"), value: clock.time(call.arrival)))
            }
            fields.append(TicketField(label: String(localized: "Orario"), value: call.scheduleOrigin.fieldValue))

        case .inPort(let call):
            fields.append(TicketField(label: String(localized: "Attracco"), value: clock.time(call.arrival)))
            if let departure = call.departure {
                fields.append(TicketField(label: String(localized: "Partenza"), value: clock.time(departure)))
            }
            fields.append(TicketField(label: String(localized: "Sosta"),
                                      value: Format.duration(call.duration),
                                      spoken: Format.duration(call.duration)))
            fields.append(TicketField(label: String(localized: "Orario"), value: call.scheduleOrigin.fieldValue))
            fields.append(contentsOf: clockFields)

        case .atSea(let from, let to):
            // Compatto: in mare la scena sopra vale più di una riga di campi.
            fields.append(TicketField(label: String(localized: "Da"),
                                      value: "\(from.name) · \(clock.time(from.castOff))"))
            fields.append(contentsOf: seaFields(from: from, to: to))
            fields.append(TicketField(label: String(localized: "Orario"), value: to.scheduleOrigin.fieldValue))
            if !clock.matchesDevice(at: now) { fields.append(contentsOf: clockFields) }

        case .completed:
            fields.append(TicketField(label: String(localized: "Scali"), value: "\(voyage.intermediateCalls.count)"))
            if let first = voyage.calls.first, let last = voyage.calls.last {
                fields.append(TicketField(label: String(localized: "Date"),
                                          value: Format.dateRange(from: first.arrival, to: last.arrival, clock: clock)))
            }
        }
        return fields
    }

    /// Velocità, rotta e miglia in mare, ognuna col nome di ciò che è davvero.
    ///
    /// Quando il GPS è fermo non dà né velocità né rotta. Invece di inventarle
    /// spacciando una media di tratta per una lettura istantanea, si cambia
    /// l'etichetta: «velocità media» e «rilevamento» sono altre grandezze.
    private func seaFields(from: PortCall, to: PortCall) -> [TicketField] {
        var fields: [TicketField] = []
        if let speed = fix?.speed, speed > 0.2 {
            fields.append(TicketField(label: String(localized: "Velocità"),
                                      value: Format.speed(knots: speed, unit: speedUnit)))
        } else {
            let hours = to.arrival.timeIntervalSince(from.castOff) / 3600
            if hours > 0 {
                let average = Geo.nauticalMiles(from: from.coordinate, to: to.coordinate) / hours
                fields.append(TicketField(label: String(localized: "Velocità media"),
                                          value: Format.speed(knots: average, unit: speedUnit)))
            }
        }
        if let fix {
            if let course = fix.course {
                fields.append(TicketField(label: String(localized: "Rotta"), value: Format.bearing(course),
                                          spoken: Format.course(course)))
            } else {
                let bearing = Geo.bearing(from: fix.coordinate, to: to.coordinate)
                fields.append(TicketField(label: String(localized: "Rilevamento"), value: Format.bearing(bearing),
                                          spoken: Format.course(bearing)))
            }
            let miles = Geo.nauticalMiles(from: fix.coordinate, to: to.coordinate)
            fields.append(TicketField(label: String(localized: "Alla meta"), value: Format.nauticalMiles(miles),
                                      spoken: String(localized: "\(Int(miles)) miglia nautiche")))
        }
        return fields
    }

    /// L'ora di bordo, e il telefono quando non concorda.
    ///
    /// È il momento in cui l'app rischia di più: chi legge crede di guardare l'ora
    /// del porto, e a bordo l'orologio dice un'altra cosa. Prima era una striscia in
    /// cima a Oggi, sempre lì per chi tiene l'ora di casa, e occupava il posto
    /// migliore della schermata. Adesso è un campo del biglietto, accanto all'ora
    /// di bordo: si legge dove si leggono gli orari.
    private var clockFields: [TicketField] {
        var fields = [TicketField(label: String(localized: "Ora di bordo"),
                                  value: "\(clock.time(now)) \(clock.offsetLabel(at: now))",
                                  spoken: clock.time(now))]
        if !clock.matchesDevice(at: now) {
            let drift = clock.deviceDrift(at: now)
            let hours = Double(drift) / 3600
            let sign = drift > 0 ? "+" : "−"
            let magnitude = hours == hours.rounded() ? "\(Int(abs(hours)))" : Format.multiplier(abs(hours)).replacingOccurrences(of: "×", with: "")
            let phone = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
            fields.append(TicketField(label: String(localized: "Il telefono"),
                                      value: "\(phone) · \(sign)\(magnitude) h",
                                      spoken: String(localized: "Il telefono segna \(phone), \(Int(abs(hours))) ore \(drift > 0 ? String(localized: "avanti") : String(localized: "indietro"))"),
                                      isSignal: true))
        }
        return fields
    }
}
