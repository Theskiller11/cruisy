import SwiftUI

/// L'itinerario, giorno per giorno: una pila di biglietti.
///
/// Ogni scalo è una matrice di biglietto, quella di oggi più alta e in risalto; i
/// giorni di mare sono lo spazio fra un biglietto e l'altro, con le onde. I giorni
/// di mare non sono righe salvate: nascono dai buchi fra uno scalo e il successivo,
/// e non possono restare indietro rispetto ai dati da cui vengono.
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
                LazyVStack(spacing: 10) {
                    ForEach(store.days) { day in
                        row(day: day, voyage: voyage)
                            .id(day.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .onAppear {
                // Si apre su oggi: è la riga che si cerca, non la prima.
                if let today = store.today { proxy.scrollTo(today.id, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func row(day: VoyageDay, voyage: Voyage) -> some View {
        switch day.content {
        case .port(let call):
            NavigationLink(value: call) {
                DayTicket(day: day, call: call, voyage: voyage, focus: store.focus, now: store.now,
                          offset: store.timeOffset,
                          photo: day.standing == .today ? portPhotos.photo(for: call) : nil)
            }
            .buttonStyle(.plain)
            // La foto si chiede **solo per lo scalo di oggi**: scaricarne una per
            // ognuno dei nove scali significherebbe nove richieste di rete
            // all'apertura di una schermata che deve funzionare anche senza rete.
            .task(id: "\(call.id)|\(reachability.isExpensive)") {
                guard day.standing == .today else { return }
                await portPhotos.load(call, allowsDownload: PhotoDownloadPolicy.allows(isMetered: reachability.isExpensive))
            }
        case .sea(let from, let to):
            SeaDayRow(day: day, from: from, to: to, voyage: voyage)
        }
    }
}

/// Un giorno in porto: una matrice di biglietto.
private struct DayTicket: View {
    @Environment(\.livery) private var livery
    let day: VoyageDay
    let call: PortCall
    let voyage: Voyage
    let focus: Voyage.Focus?
    let now: Date
    let offset: TimeInterval
    /// La foto del porto, solo per il giorno di oggi.
    var photo: CommonsPhoto?

    private var isToday: Bool { day.standing == .today }
    private var isPast: Bool { day.standing == .past }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                dateColumn
                details
                // Il passato non si attenua: si **timbra**. Una carta grigia con
                // testo grigio sembrava illeggibile — e lo era quasi — mentre un
                // timbro «toccato» dice la stessa cosa a contrasto pieno.
                if isPast {
                    Stamp(String(localized: "Toccato", comment: "Timbro"), color: livery.field, rotation: -9)
                        .scaleEffect(0.78)
                        .frame(width: 56, height: 56)
                }
                PaperDisclosure()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isToday ? 16 : 12)

            if let photo { portPhoto(photo) }
        }
        .paperCard(cornerRadius: isToday ? 18 : 14)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isToday ? [.isHeader] : [])
    }

    private var dateColumn: some View {
        VStack(spacing: 0) {
            Text(Format.weekdayAbbreviation(day.date, clock: voyage.clock))
                .ticketFieldLabel(isToday ? livery.signalInk : livery.field)
            Text(Format.dayNumber(day.date, clock: voyage.clock))
                .font(.system(.title2, weight: .black).width(.condensed))
                .monospacedDigit()
                .foregroundStyle(livery.ink)
        }
        .frame(width: 40)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(call.name)
                    .font(TicketType.place)
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let badge {
                    Text(badge)
                        .font(TicketType.stamp)
                        .tracking(0.8)
                        .foregroundStyle(livery.signalInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(livery.signal, lineWidth: 1.2))
                        .rotationEffect(.degrees(-4))
                }
            }

            Text(subtitle)
                .font(TicketType.rowDetail)
                .foregroundStyle(livery.field)
                .lineLimit(2)

            // Il countdown compare solo sulla riga di oggi: ripeterlo su ogni riga
            // toglierebbe peso proprio a quello che conta.
            if isToday, let focus, case .allAboard = focus.kind {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("Rientro \(voyage.clock.time(focus.countdown.target))")
                        .ticketFieldLabel(livery.signalInk)
                    CountdownView(countdown: focus.countdown,
                                  font: TicketType.fieldValue, offset: offset)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// La fotografia del porto di oggi, **sotto** la riga e non dietro: il testo
    /// sopra una foto qualunque non ha contrasto garantito.
    private func portPhoto(_ photo: CommonsPhoto) -> some View {
        Color.clear
            .frame(height: 132)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                // Il credito è la condizione con cui l'autore concede la foto.
                Text(photo.credit)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(6)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
    }

    private var subtitle: String {
        var parts = [Format.window(from: call.arrival, to: call.departure, clock: voyage.clock)]
        parts.append(call.berth.label)
        if let name = call.berth.name { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    private var badge: String? {
        switch day.standing {
        case .today: String(localized: "Oggi")
        case .tomorrow: String(localized: "Domani")
        case .past, .future: nil
        }
    }
}

/// Un giorno di mare: lo spazio fra due biglietti, con le onde.
private struct SeaDayRow: View {
    @Environment(\.livery) private var livery
    let day: VoyageDay
    let from: PortCall
    let to: PortCall
    let voyage: Voyage

    private var isToday: Bool { day.standing == .today }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(Format.weekdayAbbreviation(day.date, clock: voyage.clock))
                    .ticketFieldLabel(livery.onHullMuted)
                Text(Format.dayNumber(day.date, clock: voyage.clock))
                    .font(.system(.title3, weight: .black).width(.condensed))
                    .monospacedDigit()
                    .foregroundStyle(livery.onHull)
            }
            .frame(width: 40)

            Image(systemName: "water.waves")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(livery.onHullMuted)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Giorno di mare")
                        .font(TicketType.place)
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(livery.onHull)
                    if isToday {
                        Text("Oggi")
                            .font(TicketType.stamp)
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(livery.signalOnHull)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(livery.signalOnHull, lineWidth: 1.2))
                            .rotationEffect(.degrees(-4))
                    }
                }
                let miles = Geo.nauticalMiles(from: from.coordinate, to: to.coordinate)
                Text("Verso \(to.name) · \(Format.nauticalMiles(miles))")
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.onHullMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
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
