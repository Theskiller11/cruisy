import SwiftUI

/// Il dettaglio di uno scalo: il suo biglietto, la carta, come si scende, l'avviso
/// per il rientro.
struct PortDetailScreen: View {
    let call: PortCall

    @Environment(VoyageStore.self) private var store
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(MarineWeatherService.self) private var weather
    @Environment(\.livery) private var livery
    @State private var isCorrecting = false

    /// Si rilegge sempre lo scalo dallo store: se l'utente ne corregge gli orari,
    /// la copia arrivata per navigazione sarebbe vecchia di un attimo ma sbagliata
    /// per sempre.
    private var current: PortCall {
        store.voyage?.calls.first { $0.id == call.id } ?? call
    }

    private var clock: ShipClock { store.voyage?.clock ?? ShipClock(secondsFromGMT: 0) }

    private var isCurrent: Bool {
        if case .inPort(let berthed) = store.moment { return berthed.id == current.id }
        return false
    }

    var body: some View {
        ZStack {
            livery.hull.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    PortTicket(call: current, clock: clock, now: store.now, offset: store.timeOffset,
                               countdown: isCurrent ? store.focus?.countdown : nil,
                               isCurrent: isCurrent)
                        .padding(.top, 4)

                    chart
                    weatherChips
                    berthRow
                    alertCard
                    correctionRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: current.id) {
            guard current.arrival <= store.now.addingTimeInterval(3 * 86_400) else { return }
            await weather.load(for: current.coordinate, now: store.now)
        }
        .sheet(isPresented: $isCorrecting) {
            PortCallEditor(call: current, clock: clock) { amended in
                store.amend(amended)
                Task { await notifications.reschedule(for: store.voyage) }
            }
        }
    }

    /// Il tempo che troverai in questo porto, all'ora in cui ci arrivi.
    ///
    /// Solo se lo scalo è dentro la finestra dei modelli: oltre i tre giorni la
    /// previsione non esiste, e mostrare l'ultima ora disponibile spacciandola per
    /// quella dell'arrivo sarebbe peggio che non mostrare niente.
    @ViewBuilder
    private var weatherChips: some View {
        let horizon = store.now.addingTimeInterval(3 * 86_400)
        if current.arrival <= horizon,
           let conditions = weather.conditions(for: current.coordinate, at: current.arrival),
           !conditions.isEmpty,
           abs(conditions.time.timeIntervalSince(current.arrival)) < 3 * 3600 {
            VStack(alignment: .leading, spacing: 8) {
                Text("All'arrivo").ticketFieldLabel(livery.onHullMuted)
                WeatherChips(conditions: conditions, now: store.now,
                             mooring: current.berth.kind == .tender ? .tender : .alongside)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    // MARK: Pezzi

    @ViewBuilder
    private var chart: some View {
        if let voyage = store.voyage {
            SeaChart(voyage: voyage, fix: nil, now: store.now,
                     framing: .location(current.coordinate, spanDegrees: 2.6),
                     showsPortNames: true, showsGraticule: false, showsShip: false,
                     highlighting: current.coordinate)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(6)
                .paperCard()
                .accessibilityLabel(Text("Carta di \(current.name)"))
        }
    }

    private var berthRow: some View {
        PaperRow(glyph: current.berth.kind == .tender ? "sailboat.fill" : "ferry.fill",
                 title: current.berth.kind == .tender
                     ? String(localized: "Sbarco con tender")
                     : String(localized: "Ormeggio in banchina"),
                 // Col tender il margine vero è più stretto dell'all aboard: l'ultima
                 // corsa parte prima, e fa la coda. Dirlo è il motivo per cui questa
                 // riga esiste.
                 subtitle: current.berth.kind == .tender
                     ? String(localized: "L'ultima corsa parte prima dell'all aboard: calcola la coda al pontile.")
                     : current.berth.name ?? String(localized: "Si scende a piedi dalla passerella."),
                 glyphColor: current.berth.kind == .tender ? livery.signalInk : nil)
    }

    /// L'avviso prima dell'all aboard: interruttore e anticipo di sistema, su carta.
    private var alertCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { notifications.isEnabled },
                set: { newValue in
                    notifications.isEnabled = newValue
                    Task {
                        if newValue, !notifications.isAuthorised {
                            await notifications.requestAccess()
                        }
                        await notifications.reschedule(for: store.voyage)
                    }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avvisami prima dell'all aboard")
                            .font(TicketType.rowTitle)
                            .foregroundStyle(livery.ink)
                        if let allAboard = current.allAboard {
                            Text(reminderDescription(allAboard: allAboard))
                                .font(TicketType.rowDetail)
                                .foregroundStyle(livery.field)
                        }
                    }
                }
                .tint(livery.signal)

            if notifications.isEnabled {
                Picker("Anticipo", selection: Binding(
                    get: { notifications.leadMinutes },
                    set: { newValue in
                        notifications.leadMinutes = newValue
                        Task { await notifications.reschedule(for: store.voyage) }
                    })) {
                        ForEach(NotificationScheduler.leadOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
            }

            if notifications.isEnabled, notifications.authorization == .denied {
                Label("Le notifiche sono disattivate per Cruisy nelle Impostazioni di sistema: l'avviso non può suonare.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.signalInk)
            }
        }
        .padding(16)
        .paperCard()
    }

    private func reminderDescription(allAboard: Date) -> String {
        let first = allAboard.addingTimeInterval(-Double(notifications.leadMinutes) * 60)
        let final = allAboard.addingTimeInterval(-Double(NotificationScheduler.finalCallMinutes) * 60)
        return notifications.leadMinutes > NotificationScheduler.finalCallMinutes
            ? String(localized: "Alle \(clock.time(first)) e alle \(clock.time(final)), ora di bordo.")
            : String(localized: "Alle \(clock.time(first)), ora di bordo.")
    }

    private var correctionRow: some View {
        Button { isCorrecting = true } label: {
            PaperRow(glyph: "pencil",
                     title: String(localized: "Correggi gli orari"),
                     subtitle: String(localized: "Se a bordo hanno annunciato orari diversi, questi vincono su quelli pubblicati.")) {
                PaperDisclosure()
            }
        }
        .buttonStyle(.plain)
    }
}

/// Il biglietto di uno scalo qualunque: quello di oggi, uno già fatto, uno che verrà.
///
/// L'ora grande è quella del rientro a bordo — per l'imbarco quella dell'imbarco,
/// per lo sbarco quella dell'arrivo — e il timbro dice a che punto è lo scalo.
struct PortTicket: View {
    @Environment(\.livery) private var livery
    let call: PortCall
    let clock: ShipClock
    let now: Date
    var offset: TimeInterval = 0
    /// Il countdown, solo per lo scalo di oggi.
    var countdown: Countdown?
    var isCurrent = false

    private var isPast: Bool { call.castOff < now }

    private var eyebrow: String {
        switch call.role {
        case .embarkation: String(localized: "Imbarco")
        case .disembarkation: String(localized: "Sbarco")
        case .port: String(localized: "Rientro a bordo")
        }
    }

    private var hour: Date {
        switch call.role {
        case .disembarkation: call.arrival
        default: call.allAboard ?? call.castOff
        }
    }

    private var stamp: String {
        if isCurrent {
            return call.berth.kind == .tender ? String(localized: "Tender", comment: "Timbro")
                                              : String(localized: "In\nporto", comment: "Timbro")
        }
        if isPast { return String(localized: "Toccato", comment: "Timbro") }
        return String(localized: "In\nprogramma", comment: "Timbro")
    }

    var body: some View {
        Ticket {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow).ticketEyebrow(livery.signalInk).padding(.trailing, 88)
                    Text(clock.time(hour))
                        .ticketHour()
                        .foregroundStyle(livery.ink)
                        .accessibilityLabel(Text("\(eyebrow) alle \(clock.time(hour))"))
                    Text([call.name, call.region].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(TicketType.place)
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(livery.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.trailing, 80)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Stamp(stamp, color: isPast && !isCurrent ? livery.field : nil)
                    .padding(.top, 26)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 16)
        } stub: {
            VStack(alignment: .leading, spacing: 14) {
                if let countdown, now < countdown.target {
                    HStack(alignment: .lastTextBaseline) {
                        Text("Mancano").ticketFieldLabel(livery.field)
                        Spacer(minLength: 12)
                        CountdownView(countdown: countdown, offset: offset)
                    }
                    .accessibilityElement(children: .combine)
                    TicketRule()
                }
                TicketMatrix(fields: fields)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
    }

    private var fields: [TicketField] {
        var fields = [TicketField(label: String(localized: "Data"),
                                  value: Format.dayMonth(call.arrival, clock: clock))]
        fields.append(TicketField(label: String(localized: "Attracco"), value: clock.time(call.arrival)))
        if let departure = call.departure {
            fields.append(TicketField(label: String(localized: "Partenza"), value: clock.time(departure)))
            fields.append(TicketField(label: String(localized: "Sosta"),
                                      value: Format.duration(call.duration),
                                      spoken: Format.duration(call.duration)))
        }
        fields.append(TicketField(label: String(localized: "Molo"),
                                  value: call.berth.name ?? call.berth.label.capitalized))
        fields.append(TicketField(label: String(localized: "Orario"), value: call.scheduleOrigin.fieldValue))
        return fields
    }
}
