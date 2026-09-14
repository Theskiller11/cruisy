import SwiftUI

/// L'itinerario, giorno per giorno.
///
/// I giorni di mare non sono righe salvate: nascono dai buchi fra uno scalo e il
/// successivo. Correggere un orario di partenza li rifà da soli, e non possono
/// restare indietro rispetto ai dati da cui vengono.
struct ItineraryScreen: View {
    @Environment(VoyageStore.self) private var store
    @State private var route: [PortCall] = []
    @State private var isEditing = false
    @State private var isImporting = false
    @State private var isConfiguring = false
    @State private var portPhotos = PortPhotoService()
    @Environment(Reachability.self) private var reachability

    var body: some View {
        NavigationStack(path: $route) {
            ZStack {
                store.background.ignoresSafeArea()

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
                        .tint(Palette.action)
                        .accessibilityHint(Text("Correggi nave, orari e ora di bordo, o reimporta l'itinerario"))
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(voyage.shipName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(voyage.nights) notti · \(voyage.intermediateCalls.count) scali")
                                .font(.caption2)
                                .foregroundStyle(Palette.inkSecondary)
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
                LazyVStack(spacing: 8) {
                    ForEach(store.days) { day in
                        row(day: day, voyage: voyage)
                            .id(day.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
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
                DayRow(day: day, voyage: voyage, focus: store.focus, now: store.now,
                       offset: store.timeOffset, showsDisclosure: true,
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
        case .sea:
            DayRow(day: day, voyage: voyage, focus: store.focus, now: store.now,
                   offset: store.timeOffset, showsDisclosure: false)
        }
    }
}

/// Una riga dell'itinerario.
private struct DayRow: View {
    let day: VoyageDay
    let voyage: Voyage
    let focus: Voyage.Focus?
    let now: Date
    let offset: TimeInterval
    let showsDisclosure: Bool
    /// La foto del porto, solo per il giorno di oggi.
    var photo: CommonsPhoto?

    private var isToday: Bool { day.standing == .today }

    /// Il passato si attenua, ma non sparisce: resta leggibile a norma, perché
    /// "già fatto" non vuol dire "illeggibile".
    private var opacity: Double { day.standing == .past ? 0.72 : 1 }

    /// Il raggio della card.
    private var cardRadius: CGFloat { isToday ? 22 : 18 }
    /// Quanto la foto rientra dal bordo della card.
    private var photoInset: CGFloat { 10 }
    /// Il raggio della foto: quello della card **meno** il rientro.
    ///
    /// È la regola dei raccordi concentrici: perché due curve annidate restino
    /// parallele, la distanza fra loro dev'essere la stessa in ogni punto, e questo
    /// succede solo se il raggio interno è quello esterno meno il rientro. Con lo
    /// stesso raggio la foto sembra gonfia negli angoli; con un raggio più grande di
    /// quello della card, la curva interna esce da quella esterna.
    private var photoRadius: CGFloat { max(4, cardRadius - photoInset) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                dateColumn
                spine
                details
                if showsDisclosure { Disclosure() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isToday ? 15 : 12)

            if let photo { portPhoto(photo) }
        }
        .glassSurface(cornerRadius: cardRadius,
                      prominence: isToday ? .card : .chip,
                      tint: isToday ? Palette.ashore : nil)
        .opacity(opacity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isToday ? [.isHeader] : [])
    }

    /// La fotografia del porto di oggi.
    ///
    /// Sta **sotto** la riga e non dietro: il testo sopra una foto qualunque non ha
    /// contrasto garantito, e questa foto arriva da Wikipedia — può essere un cielo
    /// bianco come un molo notturno. Sotto, invece, la riga resta leggibile sempre.
    ///
    /// L'immagine va in un `overlay` e non come figlia diretta, se no il suo
    /// `.fill` detta la larghezza alla colonna e i nomi lunghi si tagliano: è lo
    /// stesso baco che ha già trasformato «Icon of the Seas» in «on of the Seas»
    /// nella scheda Nave e nella pre-crociera.
    private func portPhoto(_ photo: CommonsPhoto) -> some View {
        Color.clear
            .frame(height: 132)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            // Il ritaglio va **sull'immagine**, prima del rientro: prima stava dopo
            // il `padding` e arrotondava il riquadro già spaziato invece della foto,
            // quindi gli angoli restavano vivi. `.continuous` e non `.circular`: è
            // il supercerchio di iOS, quello con cui sono fatte le icone e le card
            // del sistema, e accanto a un raggio circolare si vede.
            .clipShape(RoundedRectangle(cornerRadius: photoRadius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                // Il credito è la condizione con cui l'autore concede la foto.
                Text(photo.credit)
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.abyss.opacity(0.7)))
                    .padding(6)
            }
            .padding(.horizontal, photoInset)
            .padding(.bottom, photoInset)
    }

    private var dateColumn: some View {
        VStack(spacing: 1) {
            Text(Format.weekdayAbbreviation(day.date, clock: voyage.clock))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Palette.ashore : Palette.inkTertiary)
            Text(Format.dayNumber(day.date, clock: voyage.clock))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.inkPrimary)
        }
        .frame(width: 38)
        .accessibilityElement(children: .combine)
    }

    /// La costola verticale: continua in porto, tratteggiata in mare — la stessa
    /// grammatica della rotta sulla carta.
    private var spine: some View {
        Group {
            if day.isSeaDay {
                Capsule()
                    .fill(Palette.action.opacity(0.45))
                    .frame(width: 1.5)
                    .mask(VStack(spacing: 3) {
                        ForEach(0..<6, id: \.self) { _ in Capsule().frame(height: 4) }
                    })
            } else {
                Capsule()
                    .fill(isToday ? Palette.ashore : Palette.hairlineStrong)
                    .frame(width: isToday ? 2.5 : 1)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                    .font(isToday ? Type.rowTitle : Type.rowDetail.weight(.semibold))
                    .foregroundStyle(Palette.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.abyss)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.ashore))
                }
            }

            Text(subtitle)
                .font(Type.rowDetail)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(2)

            // Il countdown compare solo sulla riga di oggi: ripeterlo su ogni riga
            // toglierebbe peso proprio a quello che conta.
            if isToday, let focus, case .allAboard = focus.kind {
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .semibold))
                    CountdownView(countdown: focus.countdown, size: 13, cap: 20,
                                  colour: Palette.ashore, offset: offset)
                    Text("all'all aboard")
                        .font(Type.rowDetail)
                }
                .foregroundStyle(Palette.ashore)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch day.content {
        case .port(let call): call.name
        case .sea: String(localized: "Giorno di mare")
        }
    }

    private var subtitle: String {
        switch day.content {
        case .port(let call):
            var parts = [Format.window(from: call.arrival, to: call.departure, clock: voyage.clock)]
            parts.append(call.berth.label)
            if let name = call.berth.name { parts.append(name) }
            return parts.joined(separator: " · ")
        case .sea(let from, let to):
            let miles = Geo.nauticalMiles(from: from.coordinate, to: to.coordinate)
            return String(localized: "Verso \(to.name) · \(Format.nauticalMiles(miles))")
        }
    }

    private var badge: String? {
        switch day.standing {
        case .today: String(localized: "OGGI")
        case .tomorrow: String(localized: "DOMANI")
        case .past, .future: nil
        }
    }
}

#Preview {
    ItineraryScreen()
        .environment(VoyageStore.preview)
        .environment(PositionService())
        .environment(NotificationScheduler())
        .environment(LiveActivityController())
        .environment(Reachability())
        .preferredColorScheme(.dark)
}
