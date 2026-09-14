import SwiftUI

/// Il dettaglio di uno scalo: gli orari, come si scende, e l'avviso per il rientro.
struct PortDetailScreen: View {
    let call: PortCall

    @Environment(VoyageStore.self) private var store
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(MarineWeatherService.self) private var weather
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
            store.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if isCurrent, let focus = store.focus, case .allAboard = focus.kind {
                        AllAboardHero(call: current, countdown: focus.countdown,
                                      clock: clock, now: store.now, offset: store.timeOffset)
                    } else {
                        scheduleCard
                    }

                    chart
                    weatherCard
                    berthRow
                    alertCard
                    correctionRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.large)
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
    private var weatherCard: some View {
        let horizon = store.now.addingTimeInterval(3 * 86_400)
        if current.arrival <= horizon,
           let conditions = weather.conditions(for: current.coordinate, at: current.arrival),
           !conditions.isEmpty,
           abs(conditions.time.timeIntervalSince(current.arrival)) < 3 * 3600 {
            SeaStateCard(conditions: conditions, now: store.now,
                         title: String(localized: "All'arrivo"),
                         mooring: current.berth.kind == .tender ? .tender : .alongside)
        }
    }

    // MARK: Pezzi

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AdaptiveHStack {
                Text(current.region)
                    .eyebrow()
                AdaptiveSpacer()
                ProvenanceChip(origin: current.scheduleOrigin)
            }
            Text(Format.dayMonth(current.arrival, clock: clock))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.inkPrimary)

            Divider().overlay(Palette.hairline)

            MetricRow(metrics: metrics)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 26, prominence: .card)
    }

    private var metrics: [Metric] {
        var metrics = [Metric(value: clock.time(current.arrival), label: String(localized: "Attracco"))]
        if let allAboard = current.allAboard {
            metrics.append(Metric(value: clock.time(allAboard), label: String(localized: "All aboard")))
        }
        if let departure = current.departure {
            metrics.append(Metric(value: clock.time(departure), label: String(localized: "Partenza")))
        }
        return metrics
    }

    @ViewBuilder
    private var chart: some View {
        if let voyage = store.voyage {
            SeaChart(voyage: voyage, fix: nil, now: store.now,
                     framing: .location(current.coordinate, spanDegrees: 2.6),
                     showsPortNames: true, showsGraticule: false, showsShip: false,
                     highlighting: current.coordinate)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.5))
                .accessibilityLabel(Text("Carta di \(current.name)"))
        }
    }

    private var berthRow: some View {
        InfoRow(glyph: current.berth.kind == .tender ? "sailboat.fill" : "ferry.fill",
                tint: current.berth.kind == .tender ? Palette.ashore : Palette.action,
                title: current.berth.kind == .tender
                    ? String(localized: "Sbarco con tender")
                    : String(localized: "Ormeggio in banchina"),
                // Col tender il margine vero è più stretto dell'all aboard: l'ultima
                // corsa parte prima, e fa la coda. Dirlo è il motivo per cui questa
                // riga esiste.
                subtitle: current.berth.kind == .tender
                    ? String(localized: "L'ultima corsa parte prima dell'all aboard: calcola la coda al pontile.")
                    : current.berth.name ?? String(localized: "Si scende a piedi dalla passerella."))
    }

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
                            .font(Type.rowTitle)
                            .foregroundStyle(Palette.inkPrimary)
                        if let allAboard = current.allAboard {
                            Text(reminderDescription(allAboard: allAboard))
                                .font(Type.rowDetail)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .tint(Palette.ashore)

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
                StaleDataNotice(message: "Le notifiche sono disattivate per Cruisy nelle Impostazioni di sistema: l'avviso non può suonare.")
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 22, prominence: .chip)
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
            InfoRow(glyph: "pencil", tint: Palette.action,
                    title: String(localized: "Correggi gli orari"),
                    subtitle: String(localized: "Se a bordo hanno annunciato orari diversi, questi vincono su quelli pubblicati.")) {
                Disclosure()
            }
        }
        .buttonStyle(.plain)
    }
}
