import SwiftUI

/// La sequenza di benvenuto, una volta sola: un biglietto d'imbarco che si compila.
///
/// Cinque passi, e in ognuno si **fa** qualcosa invece di leggere: si strappa la
/// matrice per salire, si timbrano le tre regole, si guarda il countdown contare
/// sulla schermata di blocco, si sceglie la nave e l'app se ne veste i colori. Alla
/// fine il biglietto porta i timbri raccolti e i campi vuoti dicono cosa manca:
/// l'itinerario, che da lì si importa.
///
/// I permessi — posizione e notifiche — **non** si chiedono qui: si chiedono quando
/// servono davvero, perché un permesso chiesto mentre si guarda la carta ha una
/// ragione evidente, e uno chiesto al primo avvio no. Ogni gesto ha anche un
/// pulsante: VoiceOver e Controllo interruttori non strappano biglietti.
struct OnboardingFlow: View {
    let onFinish: () -> Void

    @Environment(VoyageStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.livery) private var baseLivery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Int, CaseIterable {
        case welcome, promises, liveActivity, ship, itinerary
    }

    @State private var step: Step = Self.initialStep
    /// Da che parte scorrono le pagine: avanti da destra, indietro da sinistra.
    @State private var forward = true
    /// Le regole timbrate, per indice. Restano sul biglietto dell'ultimo passo.
    @State private var stamped: Set<Int> = []
    @State private var ship: ShipRecord?
    @State private var shipQuery = ""
    @FocusState private var isShipFieldFocused: Bool
    @State private var importStart: ItineraryImportView.Start?
    /// Tutta sua, non quella dell'ambiente: l'esito di una ricerca fatta qui non
    /// deve comparire nell'editor, e viceversa.
    @State private var lookup = ShipLookupService()
    /// La nave scelta non c'è né nell'elenco né su Wikidata: la si tiene col nome
    /// scritto, e lo si dice.
    @State private var keptAsTyped = false

    private static var initialStep: Step {
        #if DEBUG
        // `-onboardingStep 3` apre direttamente un passo, per poterlo verificare
        // dal simulatore senza toccare lo schermo.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-onboardingStep"),
           arguments.index(after: flag) < arguments.endIndex,
           let value = Int(arguments[arguments.index(after: flag)]) {
            return Step(rawValue: min(max(value, 0), Step.allCases.count - 1)) ?? .welcome
        }
        #endif
        return .welcome
    }

    /// La livrea: quella dell'app finché la nave non c'è, poi quella della nave
    /// scelta. Cambia sotto gli occhi, che è il modo di spiegare le livree senza
    /// spiegarle.
    private var livery: Livery {
        guard let ship else { return baseLivery }
        return Livery.resolve(preferences.livery, operatorName: ship.operatorName)
    }

    /// Il nome da proporre al riesame: la nave dell'elenco, o quello che è stato
    /// scritto se l'elenco non la conosce.
    private var shipName: String? {
        if let ship { return ship.name }
        let typed = shipQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.count >= 2 ? typed : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)

            ScrollView {
                page
                    .id(step)
                    .transition(pageTransition)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            actions
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .background { Rectangle().fill(livery.hull).ignoresSafeArea() }
        .environment(\.livery, livery)
        .interactiveDismissDisabled()
        .sheet(item: $importStart) { start in
            ItineraryImportView(start: start, shipName: shipName) { voyage in
                store.replace(with: voyage)
                finish()
            }
            .environment(\.livery, livery)
        }
    }

    // MARK: Testata

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if let previous = Step(rawValue: step.rawValue - 1) { go(to: previous) }
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(livery.onHull)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)
            .accessibilityLabel(Text("Indietro"))
            .accessibilityHidden(step == .welcome)

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(livery.onHull.opacity(item.rawValue <= step.rawValue ? 1 : 0.22))
                        .frame(height: 3)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Passo \(step.rawValue + 1) di \(Step.allCases.count)"))

            // Tiene la barra centrata rispetto al pulsante a sinistra.
            Color.clear.frame(width: 36, height: 36)
        }
    }

    // MARK: Le pagine

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .promises: promises
        case .liveActivity: liveActivity
        case .ship: shipPage
        case .itinerary: itinerary
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            HullTitle(eyebrow: "Benvenuto a bordo", title: "Quanto manca.",
                      detail: "In porto conta al rientro a bordo, in mare all'arrivo nel prossimo scalo. Nient'altro.",
                      size: 56)
            TearTicket { advance() }
        }
    }

    private var promises: some View {
        VStack(alignment: .leading, spacing: 22) {
            HullTitle(eyebrow: "Tre cose da sapere", title: "Tocca per timbrare")

            VStack(spacing: 0) {
                ForEach(Promise.all) { promise in
                    if promise.id > 0 { TicketRule().padding(.horizontal, 18) }
                    PromiseRow(promise: promise, isStamped: stamped.contains(promise.id)) {
                        stamp(promise.id)
                    }
                }
            }
            .ticketPaper()

            Text("Timbri: \(stamped.count) su \(Promise.all.count)")
                .font(TicketType.rowDetail)
                .foregroundStyle(livery.onHullMuted)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
        }
        // Il colpo del timbro si sente, oltre a vedersi.
        .sensoryFeedback(.impact(weight: .heavy), trigger: stamped.count) { old, new in new > old }
    }

    /// Il countdown sulla schermata di blocco, chiesto qui e non a bordo.
    ///
    /// Si chiede adesso perché a bordo, tre ore dall'all aboard, non è il momento
    /// di scoprire un'impostazione: è il momento di vedere il numero. E si chiede
    /// come **preferenza**, non come interruttore: qui una crociera non c'è ancora
    /// e non ci sarebbe niente da accendere. L'app se la ricorda.
    private var liveActivity: some View {
        VStack(alignment: .leading, spacing: 22) {
            HullTitle(eyebrow: "Prima di salpare", title: "Sempre sotto gli occhi",
                      detail: "Nelle ore che contano il tempo che manca sta sulla schermata di blocco e nella Dynamic Island: lo guardi senza aprire nulla.")

            LiveActivityDemo()

            Toggle(isOn: Binding(
                get: { preferences.wantsLiveActivity },
                set: { preferences.wantsLiveActivity = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mostralo quando serve")
                            .font(TicketType.rowTitle)
                            .foregroundStyle(livery.ink)
                        // La rassicurazione va detta qui, non nascosta in un aiuto:
                        // chi accetta qualcosa nell'onboarding vuole sapere di poter
                        // tornare indietro.
                        Text("Puoi disattivarlo quando vuoi dalle Impostazioni.")
                            .font(TicketType.rowDetail)
                            .foregroundStyle(livery.field)
                    }
                }
                .tint(livery.tint)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .paperCard(cornerRadius: 18)

            Text("Si accende in porto nelle ultime otto ore prima dell'all aboard, e in mare nell'ultima ora e mezza prima dell'attracco. Fuori da quelle finestre non ci sarebbe niente da contare.")
                .font(.caption)
                .foregroundStyle(livery.onHullMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// La nave prima dell'itinerario: così l'app si veste subito dei colori giusti,
    /// e il riesame ha già il nome quando il documento non lo dice — dagli
    /// screenshot della compagnia arriva spesso il marchio, non la nave.
    private var shipPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HullTitle(eyebrow: "La tua nave", title: "Su che nave sali?",
                      detail: "Cruisy si veste dei suoi colori, e la scheda della nave è già pronta.")
            if let ship {
                chosenShip(ship)
            } else {
                shipSearch
            }
            ShipArrivalScene(ship: ship)
                .padding(.horizontal, -24)
        }
    }

    private var itinerary: some View {
        VStack(alignment: .leading, spacing: 22) {
            HullTitle(eyebrow: "Ultimo passo", title: "Quasi a bordo",
                      detail: "Manca l'itinerario: la conferma della compagnia, gli screenshot della sua app o il programma di bordo.")

            Ticket {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        Text("Carta d'imbarco").ticketFieldLabel(livery.field)
                        Spacer(minLength: 8)
                        stampCluster
                    }
                    BlankField(label: "Nave", value: shipName)
                    AdaptiveHStack(verticalAlignment: .top, spacing: 14) {
                        BlankField(label: "Imbarco", value: nil)
                        BlankField(label: "Scali", value: nil)
                    }
                }
                .padding(18)
            } stub: {
                VStack(spacing: 12) {
                    Text("Da dove lo prendo?").ticketFieldLabel(livery.field)
                    AdaptiveHStack(horizontalAlignment: .center, spacing: 10) {
                        SourceButton(title: "Incolla", glyph: "doc.on.clipboard") { importStart = .paste }
                        SourceButton(title: "Foto", glyph: "photo.on.rectangle") { importStart = .photos }
                        SourceButton(title: "File", glyph: "folder") { importStart = .file }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(18)
            }
        }
    }

    // MARK: La nave

    private var shipSuggestions: [ShipRecord] {
        guard shipQuery.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        return ShipDirectory.shared.suggestions(for: shipQuery, limit: 4)
    }

    private var typedShip: String { shipQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Il nome scritto non è una nave dell'elenco: in fondo ai suggerimenti compare
    /// lui stesso, come se fosse un'altra nave, e toccandolo lo si cerca su Wikidata.
    /// Una nave varata dopo l'elenco si trova così con un tocco, senza dover capire
    /// che esiste una ricerca.
    private var offersWikidata: Bool {
        guard typedShip.count >= 3 else { return false }
        let folded = ShipDirectory.fold(typedShip)
        return !shipSuggestions.contains { ShipDirectory.fold($0.name) == folded }
    }

    /// La riga del nome scritto, nel suo stato: da cercare, in ricerca, o da riprovare.
    private var wikidataRow: some View {
        Button { searchWikidata() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(typedShip)
                        .font(TicketType.rowTitle)
                        .foregroundStyle(livery.ink)
                        .lineLimit(1)
                    Group {
                        switch lookup.outcome {
                        case .searching: Text("Cerco su Wikidata…")
                        case .failed: Text("Wikidata non risponde: tocca per riprovare")
                        default: Text("Cerca nave su Wikidata")
                        }
                    }
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.field)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if lookup.outcome == .searching {
                    ProgressView().controlSize(.small).tint(livery.ink)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(livery.field)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(lookup.outcome == .searching)
    }

    /// La ricerca parte solo dal tocco: il nome esce dal telefono perché l'hai chiesto
    /// tu, come promette l'informativa. Trovata, la nave arriva come quelle
    /// dell'elenco; non trovata, si tiene il nome scritto e si va avanti lo stesso.
    private func searchWikidata() {
        let name = typedShip
        Task {
            await lookup.search(name)
            switch lookup.outcome {
            case .found(let record):
                keptAsTyped = false
                choose(record)
            case .notFound:
                keptAsTyped = true
                choose(ShipRecord(name: name, imo: "", mmsi: "", tonnage: 0, length: 0, beam: 0,
                                  year: 0, operatorName: "", flag: "", imageFile: ""))
            default:
                break
            }
        }
    }

    private var shipSearch: some View {
        VStack(spacing: 10) {
            TextField("Nome della nave", text: $shipQuery,
                      prompt: Text("Nome della nave").foregroundStyle(livery.field))
                .font(.title3.weight(.semibold))
                .foregroundStyle(livery.ink)
                .tint(livery.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isShipFieldFocused)
                .onSubmit {
                    if let match = ShipDirectory.shared.lookup(shipQuery) { choose(match) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .paperCard(cornerRadius: 14)

            if !shipSuggestions.isEmpty || offersWikidata {
                VStack(spacing: 0) {
                    ForEach(Array(shipSuggestions.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { TicketRule().padding(.leading, 16) }
                        Button { choose(record) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.name)
                                    .font(TicketType.rowTitle)
                                    .foregroundStyle(livery.ink)
                                if let detail = Self.detail(of: record) {
                                    Text(detail)
                                        .font(TicketType.rowDetail)
                                        .foregroundStyle(livery.field)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if offersWikidata {
                        if !shipSuggestions.isEmpty { TicketRule().padding(.leading, 16) }
                        wikidataRow
                    }
                }
                .paperCard(cornerRadius: 14)
            }
        }
        // Un nome nuovo è una ricerca nuova: l'esito di quella di prima non vale più.
        .onChange(of: shipQuery) { _, _ in
            if lookup.outcome != .searching { lookup.reset() }
        }
    }

    private func chosenShip(_ record: ShipRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "ferry.fill")
                    .font(.title2)
                    .foregroundStyle(livery.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(livery.ink)
                    if let detail = Self.detail(of: record) {
                        Text(detail)
                            .font(TicketType.rowDetail)
                            .foregroundStyle(livery.field)
                    }
                }
                Spacer(minLength: 8)
                Button("Cambia") { clearShip() }
                    .font(TicketType.rowTitle)
                    .tint(livery.tint)
            }
            .padding(16)
            .paperCard(cornerRadius: 14)
            .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))

            if keptAsTyped {
                Text("Su Wikidata non c'è: la tengo col nome che hai scritto.")
                    .font(.caption)
                    .foregroundStyle(livery.onHullMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Il nome della compagnia non compare: le livree sono colori ispirati,
            // mai un marchio (App Store 5.2.1).
            if livery.id != Livery.cruisy.id {
                Text("Colori ispirati alla compagnia della nave. Se preferisci quelli di Cruisy, si cambiano nelle Impostazioni.")
                    .font(.caption)
                    .foregroundStyle(livery.onHullMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func detail(of record: ShipRecord) -> String? {
        var parts: [String] = []
        if record.year > 0 { parts.append(String(record.year)) }
        if record.tonnage > 0 {
            parts.append(record.tonnage.formatted(.number.precision(.fractionLength(0))) + " t")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func choose(_ record: ShipRecord) {
        isShipFieldFocused = false
        withAnimation(Motion.honouring(reduceMotion, .easeInOut(duration: 0.6))) {
            ship = record
            shipQuery = record.name
        }
    }

    private func clearShip() {
        keptAsTyped = false
        lookup.reset()
        withAnimation(Motion.honouring(reduceMotion, .easeInOut(duration: 0.4))) { ship = nil }
        isShipFieldFocused = true
    }

    // MARK: I timbri

    private func stamp(_ id: Int) {
        guard !stamped.contains(id) else { return }
        // L'unico rimbalzo della sequenza: il timbro cade dove il dito ha battuto,
        // e un timbro vero rimbalza.
        withAnimation(reduceMotion ? Motion.reduced : .spring(response: 0.3, dampingFraction: 0.55)) {
            _ = stamped.insert(id)
        }
    }

    /// I timbri raccolti, uno sull'altro, nell'angolo del biglietto finale.
    private var stampCluster: some View {
        ZStack(alignment: .trailing) {
            ForEach(stamped.sorted(), id: \.self) { id in
                // Sotto i 58 punti «VISTO» non sta più su una riga e il timbro lo spezza.
                Stamp(String(localized: "Visto"), rotation: Promise.angle(id), diameter: 60)
                    .offset(x: CGFloat(id) * -34, y: CGFloat(id % 2) * 8)
            }
        }
        .frame(width: 132, height: 68, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Timbri: \(stamped.count) su \(Promise.all.count)"))
        .accessibilityHidden(stamped.isEmpty)
    }

    // MARK: Comandi

    @ViewBuilder
    private var actions: some View {
        switch step {
        case .welcome:
            Button("Inizia") { advance() }
                .buttonStyle(HullButtonStyle(kind: .quiet, livery: livery))
        case .promises:
            // Si può andare avanti anche senza timbrare: il pulsante si accende al
            // terzo timbro, ma non trattiene nessuno.
            Button("Avanti") { advance() }
                .buttonStyle(HullButtonStyle(kind: stamped.count == Promise.all.count ? .primary : .secondary,
                                             livery: livery))
        case .liveActivity, .ship:
            Button("Avanti") { advance() }
                .buttonStyle(HullButtonStyle(kind: .primary, livery: livery))
        case .itinerary:
            Button("Lo faccio più tardi") { finish() }
                .buttonStyle(HullButtonStyle(kind: .quiet, livery: livery))
        }
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { go(to: next) }
    }

    private func go(to target: Step) {
        isShipFieldFocused = false
        forward = target.rawValue > step.rawValue
        // La direzione deve arrivare alla pagina che esce **prima** che esca: cambiata
        // nello stesso aggiornamento, la pagina tolta userebbe la transizione vecchia.
        Task { @MainActor in
            withAnimation(Motion.honouring(reduceMotion, Motion.settle)) { step = target }
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

// MARK: - Le tre regole

private struct Promise: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    static var all: [Promise] { [
        Promise(id: 0, title: "Gli annunci di bordo fanno fede",
                text: "Cruisy conta dagli orari che le hai dato. Se a bordo ne annunciano altri, vincono loro: si correggono con un tocco."),
        Promise(id: 1, title: "Funziona senza rete",
                text: "Countdown e carta si calcolano sul telefono. In mezzo all'oceano, in modalità aereo, continuano a funzionare."),
        Promise(id: 2, title: "Conta in ora di bordo",
                text: "Le navi tengono la propria ora e non sempre la cambiano in porto. Se il telefono non è allineato, Cruisy te lo dice."),
    ] }

    /// Ogni timbro con la sua inclinazione: tre timbri dritti uguali sembrano stampati.
    static func angle(_ id: Int) -> Double { [-14, 9, -4][id % 3] }
}

private struct PromiseRow: View {
    let promise: Promise
    let isStamped: Bool
    let onStamp: () -> Void

    @Environment(\.livery) private var livery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onStamp) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: String(format: "%02d", promise.id + 1))
                        .ticketFieldLabel(livery.field)
                    Text(promise.title)
                        .font(TicketType.rowTitle)
                        .foregroundStyle(livery.ink)
                    Text(promise.text)
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.field)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    if isStamped {
                        Stamp(String(localized: "Visto"), rotation: Promise.angle(promise.id), diameter: 58)
                            .transition(reduceMotion ? .opacity : .scale(scale: 2.2).combined(with: .opacity))
                    } else {
                        Circle()
                            .stroke(livery.perforation, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .padding(6)
                            .overlay(Text("tocca").font(TicketType.fieldLabel).foregroundStyle(livery.field))
                            .transition(.opacity)
                    }
                }
                .frame(width: 58, height: 58)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(promise.title) + Text(verbatim: ". ") + Text(promise.text))
        .accessibilityValue(isStamped ? Text("Timbrato") : Text("Da timbrare"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Il biglietto da strappare

/// Il biglietto del benvenuto: si trascina il dito lungo la perforazione e la
/// matrice si stacca, dalla sinistra, finché non cade.
private struct TearTicket: View {
    let onTorn: () -> Void

    @Environment(\.livery) private var livery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var isTorn = false
    @State private var width: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            top
                .background(HalfTicketShape(notchesAt: .bottom).fill(livery.paper))
            stub
                .background(HalfTicketShape(notchesAt: .top).fill(livery.paper))
                .overlay(alignment: .top) { Perforation() }
                // Il perno è l'angolo in alto a destra: la matrice si apre da sinistra,
                // dove il dito ha cominciato a strappare.
                .rotationEffect(.degrees(isTorn ? 20 : Double(progress) * 7), anchor: .topTrailing)
                .offset(y: isTorn && !reduceMotion ? 420 : 0)
                .opacity(isTorn ? 0 : 1)
                .gesture(tearGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Strappa il biglietto per iniziare"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { tear() }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = max($0, 1) }
        // Un tic a ogni tratto di perforazione, un colpo quando si stacca.
        .sensoryFeedback(.selection, trigger: Int(progress * 8))
        .sensoryFeedback(.impact(weight: .medium), trigger: isTorn) { _, torn in torn }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Carta d'imbarco").ticketFieldLabel(livery.field)
                Spacer()
                Text(verbatim: "Nº 0001").ticketFieldLabel(livery.field)
            }
            TicketMatrix(fields: [
                TicketField(label: String(localized: "Passeggero"), value: "—",
                            spoken: String(localized: "da scrivere")),
                TicketField(label: String(localized: "Nave"), value: String(localized: "da scegliere")),
            ])
            TicketRule()
            VStack(alignment: .leading, spacing: 2) {
                Text("Destinazione").ticketFieldLabel(livery.field)
                Text("Ovunque")
                    .font(.system(.largeTitle, weight: .black).width(.condensed))
                    .textCase(.uppercase)
                    .foregroundStyle(livery.ink)
            }
        }
        .padding(18)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var stub: some View {
        HStack(spacing: 8) {
            Text("Strappa per iniziare").ticketEyebrow(livery.signalInk)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.heavy))
                .foregroundStyle(livery.signalInk)
                .phaseAnimator(reduceMotion ? [0] : [0, 6]) { arrow, shift in
                    arrow.offset(x: shift)
                } animation: { _ in .easeInOut(duration: 0.7) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .contentShape(Rectangle())
    }

    private var tearGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isTorn else { return }
                progress = min(max(value.translation.width / (width * 0.6), 0), 1)
                if progress >= 1 { tear() }
            }
            .onEnded { _ in
                guard !isTorn else { return }
                withAnimation(Motion.sheet) { progress = 0 }
            }
    }

    private func tear() {
        guard !isTorn else { return }
        withAnimation(reduceMotion ? Motion.reduced : .easeIn(duration: 0.45)) { isTorn = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 420))
            onTorn()
        }
    }
}

/// Mezza carta: la parte alta del biglietto, o la matrice, con i due mezzi incavi
/// sul lato della perforazione. Separate, perché la matrice si stacca davvero.
private struct HalfTicketShape: Shape {
    enum Side { case top, bottom }
    var notchesAt: Side
    var cornerRadius: CGFloat = 18
    var notchRadius: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        let radii = notchesAt == .bottom
            ? RectangleCornerRadii(topLeading: cornerRadius, bottomLeading: 0,
                                   bottomTrailing: 0, topTrailing: cornerRadius)
            : RectangleCornerRadii(topLeading: 0, bottomLeading: cornerRadius,
                                   bottomTrailing: cornerRadius, topTrailing: 0)
        let paper = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
        let y = notchesAt == .bottom ? rect.maxY : rect.minY
        var notches = Path()
        for x in [rect.minX, rect.maxX] {
            notches.addEllipse(in: CGRect(x: x - notchRadius, y: y - notchRadius,
                                          width: notchRadius * 2, height: notchRadius * 2))
        }
        return paper.subtracting(notches)
    }
}

// MARK: - Pezzi

/// Il titolo di ogni pagina, sullo scafo: etichetta, titolo stretto e nero, testo.
private struct HullTitle: View {
    @Environment(\.livery) private var livery
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    init(eyebrow: LocalizedStringKey, title: LocalizedStringKey,
         detail: LocalizedStringKey? = nil, size: CGFloat = 40) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).ticketEyebrow(livery.onHullMuted)
            Text(title)
                .font(.system(size: min(size, 72), weight: .black).width(.condensed))
                .foregroundStyle(livery.onHull)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(TicketType.body)
                    .foregroundStyle(livery.onHullMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Un campo del biglietto finale: il valore se c'è, se no la riga da riempire.
private struct BlankField: View {
    @Environment(\.livery) private var livery
    let label: LocalizedStringKey
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ticketFieldLabel(livery.field)
            if let value {
                Text(value)
                    .font(TicketType.fieldValue)
                    .foregroundStyle(livery.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                BlankLine()
                    .stroke(livery.perforation, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(maxWidth: 120, maxHeight: 1.5)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(value.map { Text($0) } ?? Text("da riempire"))
    }

    private struct BlankLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// Una delle tre strade per l'itinerario, nella matrice del biglietto finale.
private struct SourceButton: View {
    @Environment(\.livery) private var livery
    let title: LocalizedStringKey
    let glyph: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.title3.weight(.semibold))
                    .frame(height: 26)
                    .accessibilityHidden(true)
                Text(title)
                    .font(TicketType.rowTitle)
            }
            .foregroundStyle(livery.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(livery.rule))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressedScale())
    }
}

private struct PressedScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// I pulsanti sullo scafo: pieno bianco per andare avanti, bordato quando è
/// possibile ma non ancora il momento, solo testo per le uscite.
private struct HullButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    let kind: Kind
    let livery: Livery

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(kind == .primary ? livery.hull : kind == .quiet ? livery.onHullMuted : livery.onHull)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                switch kind {
                case .primary: Capsule().fill(livery.onHull)
                case .secondary: Capsule().stroke(livery.onHull.opacity(0.4), lineWidth: 1)
                case .quiet: EmptyView()
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
