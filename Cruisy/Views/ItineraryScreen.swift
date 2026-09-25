import SwiftUI

/// L'itinerario, giorno per giorno: una linea del tempo.
///
/// Il passato sbiadisce nello scafo, lo scalo di oggi è un biglietto, quelli che
/// devono venire sono di carta; i giorni di mare stanno sulla rotaia fra uno e
/// l'altro. I giorni di mare non sono righe salvate: nascono dai buchi fra uno
/// scalo e il successivo, e non possono restare indietro rispetto ai dati da cui
/// vengono.
struct ItineraryScreen: View {
    @Environment(VoyageStore.self) private var store
    @Environment(\.livery) private var livery
    @State private var route: [PortCall] = []
    @State private var isEditing = false
    @State private var isImporting = false
    @State private var isConfiguring = false
    @State private var portPhotos = PortPhotoService()
    @Environment(Reachability.self) private var reachability

    var body: some View {
        NavigationStack(path: $route) {
            ZStack {
                livery.hull.ignoresSafeArea()

                if let voyage = store.voyage {
                    list(voyage: voyage)
                } else {
                    NoVoyageView()
                }
            }
            .navigationTitle("Itinerario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if let voyage = store.voyage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Modifica a mano", systemImage: "pencil") { isEditing = true }
                            Button("Importa di nuovo", systemImage: "text.viewfinder") { isImporting = true }
                            Divider()
                            Button("Impostazioni", systemImage: "gearshape") { isConfiguring = true }
                        } label: {
                            Text("Modifica")
                        }
                        .accessibilityHint(Text("Correggi nave, orari e ora di bordo, o reimporta l'itinerario"))
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(voyage.shipName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(voyage.nights) notti · \(voyage.intermediateCalls.count) scali")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationDestination(for: PortCall.self) { PortDetailScreen(call: $0) }
            .sheet(isPresented: $isEditing) {
                VoyageEditor(voyage: store.voyage) { store.replace(with: $0) }
            }
            .sheet(isPresented: $isImporting) {
                ItineraryImportView { store.replace(with: $0) }
            }
            .sheet(isPresented: $isConfiguring) { SettingsSheet() }
            #if DEBUG
            .task {
                switch DebugLaunch.open {
                case "editor": isEditing = true
                case "importazione": isImporting = true
                case "impostazioni": isConfiguring = true
                case "scalo":
                    // Lo scalo di oggi se c'è, se no il prossimo: è quello che si guarda.
                    let now = store.now
                    if let call = store.voyage?.calls.first(where: { $0.castOff >= now }) {
                        route = [call]
                    }
                default: break
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func list(voyage: Voyage) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let today = store.today {
                        TripProgress(days: store.days, today: today)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.days.enumerated()), id: \.element.id) { index, day in
                            row(day: day, voyage: voyage,
                                isFirst: index == 0, isLast: index == store.days.count - 1)
                                .id(day.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .shrinksTabBar()
            .onAppear {
                // Si apre su oggi: è la riga che si cerca, non la prima.
                if let today = store.today { proxy.scrollTo(today.id, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func row(day: VoyageDay, voyage: Voyage, isFirst: Bool, isLast: Bool) -> some View {
        switch day.content {
        case .port(let call):
            NavigationLink(value: call) {
                TimelineRow(day: day, clock: voyage.clock, isFirst: isFirst, isLast: isLast,
                            node: day.standing == .past ? .touched : day.standing == .today ? .today : .port) {
                    switch day.standing {
                    case .past:
                        PastPort(call: call, clock: voyage.clock)
                    case .today:
                        TodayPort(call: call, clock: voyage.clock, focus: store.focus,
                                  offset: store.timeOffset, photo: portPhotos.photo(for: call))
                    case .tomorrow, .future:
                        FuturePort(call: call, clock: voyage.clock, isTomorrow: day.standing == .tomorrow)
                    }
                }
            }
            .buttonStyle(.plain)
            // La foto si chiede **solo per lo scalo di oggi**: scaricarne una per
            // ognuno dei nove scali significherebbe nove richieste di rete
            // all'apertura di una schermata che deve funzionare anche senza rete.
            .task(id: "\(call.id)|\(reachability.isExpensive)") {
                guard day.standing == .today else { return }
                await portPhotos.load(call, allowsDownload: PhotoDownloadPolicy.allows(isMetered: reachability.isExpensive))
            }
        case .sea(_, let to):
            let from = seaOrigin(day: day)
            TimelineRow(day: day, clock: voyage.clock, isFirst: isFirst, isLast: isLast,
                        node: day.standing == .today ? .today : .sea) {
                SeaDay(from: from, to: to, isToday: day.standing == .today, isPast: day.standing == .past)
            }
        }
    }

    private func seaOrigin(day: VoyageDay) -> PortCall? {
        if case .sea(let from, _) = day.content { return from }
        return nil
    }
}

// MARK: - La linea del tempo

/// A che punto è la crociera: un segmento per giorno, pieni quelli passati,
/// arancio quello di oggi.
private struct TripProgress: View {
    @Environment(\.livery) private var livery
    let days: [VoyageDay]
    let today: VoyageDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(days) { day in
                    Capsule()
                        .fill(colour(day))
                        .frame(height: 4)
                }
            }
            Text("Giorno \(today.number) di \(days.count)")
                .ticketFieldLabel(livery.onHullMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Giorno \(today.number) di \(days.count)"))
    }

    private func colour(_ day: VoyageDay) -> Color {
        switch day.standing {
        case .past: livery.onHull.opacity(0.8)
        case .today: livery.signalOnHull
        case .tomorrow, .future: livery.onHull.opacity(0.2)
        }
    }
}

/// Una riga della linea del tempo: la data, la rotaia col suo nodo, il contenuto.
///
/// Prima l'itinerario era una pila di biglietti tutti uguali, col passato
/// timbrato «toccato» e il futuro identico al presente. Qui si legge come un
/// viaggio: il passato sbiadisce nello scafo, oggi è un biglietto vero, il futuro
/// è di carta; la rotaia è piena fin dove si è arrivati e tratteggiata dopo.
private struct TimelineRow<Content: View>: View {
    @Environment(\.livery) private var livery
    @Environment(\.dynamicTypeSize) private var typeSize
    let day: VoyageDay
    let clock: ShipClock
    let isFirst: Bool
    let isLast: Bool
    let node: TimelineNode.Kind
    @ViewBuilder let content: () -> Content

    /// Dove cade il nodo, dall'alto della riga: all'altezza del nome.
    private var nodeY: CGFloat { node == .today ? 30 : 22 }
    private let railWidth: CGFloat = 22

    var body: some View {
        let accessible = typeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 10) {
            if !accessible {
                dateBadge
                    .frame(width: 38)
                    .padding(.top, nodeY - 16)
            }
            Color.clear.frame(width: railWidth)
            VStack(alignment: .leading, spacing: 6) {
                // Ai corpi accessibili la data va sopra il contenuto: nella colonna
                // da 38 punti il giorno della settimana andava a capo.
                if accessible { dateLine }
                content()
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(alignment: .topLeading) {
            rail
                .frame(width: railWidth)
                .padding(.leading, accessible ? 0 : 48)
        }
        .opacity(day.standing == .past ? 0.92 : 1)
    }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            Text(Format.weekdayAbbreviation(day.date, clock: clock))
                .ticketFieldLabel(day.standing == .today ? livery.signalOnHull : livery.onHullMuted)
            Text(Format.dayNumber(day.date, clock: clock))
                .font(.system(.title2, weight: .black).width(.condensed))
                .monospacedDigit()
                .foregroundStyle(livery.onHull.opacity(day.standing == .past ? 0.6 : 1))
        }
        .accessibilityElement(children: .combine)
    }

    private var dateLine: some View {
        Text("\(Format.weekdayAbbreviation(day.date, clock: clock)) \(Format.dayNumber(day.date, clock: clock))")
            .font(.system(.title3, weight: .black).width(.condensed))
            .monospacedDigit()
            .foregroundStyle(day.standing == .today ? livery.signalOnHull : livery.onHull)
    }

    /// La rotaia: piena fin dove si è arrivati, tratteggiata dopo.
    private var rail: some View {
        let reachedAbove = day.standing == .past || day.standing == .today
        let reachedBelow = day.standing == .past
        return ZStack(alignment: .top) {
            Canvas { context, size in
                let x = size.width / 2
                func segment(from y0: CGFloat, to y1: CGFloat, solid: Bool) {
                    guard y1 > y0 else { return }
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y0))
                    path.addLine(to: CGPoint(x: x, y: y1))
                    context.stroke(path, with: .color(livery.onHull.opacity(solid ? 0.35 : 0.3)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: solid ? [] : [2, 5]))
                }
                if !isFirst { segment(from: 0, to: nodeY - 9, solid: reachedAbove) }
                if !isLast { segment(from: nodeY + 9, to: size.height, solid: reachedBelow) }
            }
            TimelineNode(kind: node)
                .frame(width: 22, height: 22)
                .padding(.top, nodeY - 11)
        }
        .accessibilityHidden(true)
    }
}

/// Il nodo sulla rotaia: toccato, oggi, scalo da venire, giorno di mare.
private struct TimelineNode: View {
    enum Kind { case touched, today, port, sea }
    @Environment(\.livery) private var livery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: Kind
    @State private var pulse = false

    var body: some View {
        switch kind {
        case .touched:
            Circle().fill(livery.onHullMuted)
                .frame(width: 14, height: 14)
                .overlay(Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(livery.hull))
        case .today:
            ZStack {
                // Il punto di oggi respira: è l'unica cosa che si muove nella lista.
                Circle().stroke(livery.signalOnHull, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulse ? 1.25 : 0.7)
                    .opacity(pulse ? 0 : 0.8)
                Circle().fill(livery.signalOnHull).frame(width: 14, height: 14)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
            }
        case .port:
            Circle().fill(livery.hull)
                .overlay(Circle().stroke(livery.onHull, lineWidth: 2))
                .frame(width: 12, height: 12)
        case .sea:
            Circle().fill(livery.hull)
                .overlay(Circle().stroke(livery.onHullMuted, lineWidth: 1.5))
                .frame(width: 9, height: 9)
        }
    }
}

// MARK: - I giorni

private func portSubtitle(_ call: PortCall, clock: ShipClock) -> String {
    var parts = [Format.window(from: call.arrival, to: call.departure, clock: clock)]
    parts.append(call.berth.label)
    if let name = call.berth.name { parts.append(name) }
    return parts.joined(separator: " · ")
}

/// Uno scalo passato: niente carta, il nome e gli orari sullo scafo, attenuati.
/// La spunta sul nodo dice «toccato» al posto del timbro.
private struct PastPort: View {
    @Environment(\.livery) private var livery
    let call: PortCall
    let clock: ShipClock

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(call.name)
                    .font(TicketType.place)
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.onHull.opacity(0.72))
                    .lineLimit(2)
                Text(portSubtitle(call, clock: clock))
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.onHullMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(livery.onHullMuted)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("Toccato"))
    }
}

/// Uno scalo che deve venire: una card di carta, col timbro «domani» se è domani.
private struct FuturePort: View {
    @Environment(\.livery) private var livery
    let call: PortCall
    let clock: ShipClock
    let isTomorrow: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                // Il timbro accanto al nome, non in fondo alla riga: là stringeva gli
                // orari e li mandava a capo.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(call.name)
                        .font(TicketType.place)
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(livery.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if isTomorrow { StampBadge(String(localized: "Domani")) }
                }
                Text(portSubtitle(call, clock: clock))
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.field)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PaperDisclosure()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .paperCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Lo scalo di oggi: un biglietto vero, con la foto piccola e il rientro in matrice.
private struct TodayPort: View {
    @Environment(\.livery) private var livery
    let call: PortCall
    let clock: ShipClock
    let focus: Voyage.Focus?
    let offset: TimeInterval
    var photo: CommonsPhoto?

    var body: some View {
        Ticket(cornerRadius: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Oggi · in porto").ticketEyebrow(livery.signalInk)
                    Text(call.name)
                        .font(.system(.title2, weight: .black).width(.condensed))
                        .textCase(.uppercase)
                        .foregroundStyle(livery.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(portSubtitle(call, clock: clock))
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.field)
                    // Il credito è la condizione con cui l'autore concede la foto:
                    // la miniatura è piccola, il nome resta scritto per intero.
                    if let photo {
                        Text(photo.credit)
                            .font(.caption2)
                            .foregroundStyle(livery.field)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let photo {
                    Color.clear
                        .frame(width: 62, height: 62)
                        .overlay {
                            Image(uiImage: photo.image).resizable().aspectRatio(contentMode: .fill)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
        } stub: {
            HStack(alignment: .firstTextBaseline) {
                Text(stubLabel).ticketFieldLabel(isAllAboard ? livery.signalInk : livery.field)
                Spacer(minLength: 8)
                if let focus {
                    CompactCountdown(countdown: focus.countdown, offset: offset)
                        .font(TicketType.count)
                        .foregroundStyle(livery.ink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private var isAllAboard: Bool {
        if case .allAboard = focus?.kind { return true }
        return false
    }

    private var stubLabel: String {
        if let focus, isAllAboard {
            return String(localized: "Rientro \(clock.time(focus.countdown.target))")
        }
        return String(localized: "Partenza \(clock.time(call.castOff))")
    }
}

/// Un giorno di mare: sulla rotaia, senza carta, con le miglia.
private struct SeaDay: View {
    @Environment(\.livery) private var livery
    let from: PortCall?
    let to: PortCall
    let isToday: Bool
    let isPast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Giorno di mare")
                    .font(TicketType.rowTitle)
                    .foregroundStyle(livery.onHull.opacity(isPast ? 0.72 : 1))
                if isToday { StampBadge(String(localized: "Oggi"), color: livery.signalOnHull) }
            }
            Text(detail)
                .font(TicketType.rowDetail)
                .foregroundStyle(livery.onHullMuted)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard let from else { return String(localized: "Verso \(to.name)") }
        let miles = Geo.nauticalMiles(from: from.coordinate, to: to.coordinate)
        return String(localized: "Verso \(to.name) · \(Format.nauticalMiles(miles))")
    }
}

#Preview {
    ItineraryScreen()
        .environment(VoyageStore.preview)
        .environment(Preferences.ephemeral)
        .environment(PositionService())
        .environment(NotificationScheduler())
        .environment(LiveActivityController())
        .environment(Reachability())
        .preferredColorScheme(.dark)
}
