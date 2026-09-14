import Foundation
import SwiftUI
import Observation

/// Lo stato dell'app: la crociera, l'istante corrente, le preferenze.
///
/// `now` si aggiorna al minuto, non al secondo. I secondi servono solo dentro il
/// countdown, che li rende da sé con `TimelineView`: far ridisegnare l'intera
/// schermata una volta al secondo costerebbe batteria a bordo, dove ricaricare
/// non è sempre comodo.
@Observable
final class VoyageStore {

    // MARK: Stato

    private(set) var voyage: Voyage?
    /// L'istante su cui è impaginata la schermata.
    private(set) var now: Date = .now
    /// Scarto fra l'ora vera e il punto di osservazione. Zero in produzione; lo usa
    /// solo il collaudo, per mettersi a venti minuti dall'all aboard senza aspettare.
    private(set) var timeOffset: TimeInterval = 0
    var speedUnit: SpeedUnit = .knots {
        didSet { UserDefaults.standard.set(speedUnit.rawValue, forKey: Keys.speedUnit) }
    }
    /// Chi usa l'app ha già letto e accettato l'avviso sull'attendibilità degli orari.
    var hasSeenDisclaimer: Bool = false {
        didSet { UserDefaults.standard.set(hasSeenDisclaimer, forKey: Keys.disclaimer) }
    }
    /// Vuole il countdown sulla schermata di blocco.
    ///
    /// È una preferenza e non un interruttore momentaneo perché la si chiede
    /// nell'onboarding, quando una crociera non c'è ancora e non ci sarebbe niente
    /// da accendere. L'app se la ricorda e accende l'attività da sé quando arriva
    /// il momento — e resta spegnibile in qualunque istante.
    var wantsLiveActivity: Bool = false {
        didSet { UserDefaults.standard.set(wantsLiveActivity, forKey: Keys.liveActivity) }
    }

    /// Vuole che l'app registri la rotta davvero percorsa.
    ///
    /// È una preferenza e non un interruttore momentaneo, come quella della Live
    /// Activity: la si accende una volta e vale per la crociera. Costa batteria e
    /// costa il permesso di posizione permanente, quindi non è mai accesa da sé.
    var wantsTracking: Bool = false {
        didSet { UserDefaults.standard.set(wantsTracking, forKey: Keys.tracking) }
    }

    /// La rotta percorsa dalla crociera in corso.
    private(set) var track = Track()
    /// Quanti punti c'erano l'ultima volta che si è scritto su disco.
    private var savedTrackPoints = 0

    /// Il diario, che sopravvive alle crociere.
    private(set) var logbook = Logbook()
    /// Quanti scali della crociera corrente sono già finiti nel diario. Serve solo
    /// a non riscrivere il file a ogni battito dell'orologio.
    private var loggedCallCount = 0
    /// Vero quando la crociera in corso è uno scenario di collaudo. Il diario la
    /// mostra — se no in DEBUG sarebbe sempre vuoto — ma non la scrive su disco:
    /// i dati di prova non devono sporcare le miglia di nessuno.
    private var isDemo = false
    /// Uno store che non deve toccare il disco: anteprime e test.
    ///
    /// Senza questo, un'anteprima di SwiftUI che chiama `replace` sovrascrive la
    /// crociera vera di chi sta usando l'app. Non è teoria: è successo a un test,
    /// che ha cancellato l'archivio di un altro.
    private let isEphemeral: Bool

    private var ticker: Timer?

    private enum Keys {
        static let speedUnit = "cruisy.speedUnit"
        static let disclaimer = "cruisy.hasSeenDisclaimer"
        static let liveActivity = "cruisy.wantsLiveActivity"
        static let tracking = "cruisy.wantsTracking"
    }

    // MARK: Ciclo di vita

    init(voyage: Voyage? = nil, now: Date = .now, timeOffset: TimeInterval = 0, autoload: Bool = true) {
        self.isEphemeral = !autoload
        self.timeOffset = timeOffset
        self.now = now.addingTimeInterval(timeOffset)
        if let voyage {
            self.voyage = voyage
        } else if autoload, let scenario = Self.debugScenario() {
            self.voyage = scenario.voyage
            self.isDemo = true
            self.timeOffset = scenario.timeOffset
            self.now = now.addingTimeInterval(scenario.timeOffset)
        } else if autoload {
            // Riconciliata al caricamento: una crociera salvata prima dei fusi
            // non ne ha nessuno, e senza questo l'ora di bordo non cambierebbe mai.
            self.voyage = Self.reconciled(VoyageArchive.load())
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.speedUnit),
           let unit = SpeedUnit(rawValue: raw) {
            speedUnit = unit
        }
        hasSeenDisclaimer = UserDefaults.standard.bool(forKey: Keys.disclaimer)
        wantsTracking = UserDefaults.standard.bool(forKey: Keys.tracking)
        if autoload {
            track = TrackArchive.load()
            savedTrackPoints = track.points.count
        }
        wantsLiveActivity = UserDefaults.standard.bool(forKey: Keys.liveActivity)
        if !isEphemeral { logbook = LogbookArchive.load() }
        recordProgress()
        startTicking()
    }

    deinit { ticker?.invalidate() }

    /// Riallinea `now` al minuto. Il passaggio fra porto e mare, o fra un giorno e
    /// l'altro, non ha bisogno di una precisione più fine.
    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Da chiamare quando l'app torna in primo piano: mentre era sospesa il tempo
    /// è passato lo stesso.
    func refresh() {
        now = Date().addingTimeInterval(timeOffset)
        recordProgress()
    }

    // MARK: Il diario
    //
    // Un porto entra nel diario quando ci sei arrivato, non quando lo cancelli dalla
    // crociera: se aspettassimo la fine del viaggio, sostituire l'itinerario a metà
    // rotta cancellerebbe metà diario.

    /// Riporta nel diario la parte di crociera già percorsa.
    ///
    /// Si chiama spesso — a ogni battito e a ogni modifica — ma tocca il disco solo
    /// quando c'è davvero uno scalo in più da segnare.
    private func recordProgress(force: Bool = false) {
        guard let voyage else { return }
        let entry = LoggedVoyage.sailed(voyage, upTo: now)
        guard force || entry.ports.count != loggedCallCount else { return }
        loggedCallCount = entry.ports.count
        logbook.record(entry)
        guard !isDemo, !isEphemeral else { return }
        try? LogbookArchive.save(logbook)
    }

    // MARK: La rotta percorsa

    /// Segna un punto, se porta informazione.
    ///
    /// La decide `Track.append`: un quarto di miglio e due minuti di distanza dal
    /// punto precedente. Il filtro sta nel modello e non qui, così vale allo stesso
    /// modo per il GPS in primo piano e per quello in background.
    func record(fix: Coordinate, at instant: Date) {
        guard voyage != nil, !isEphemeral else { return }
        guard track.append(TrackPoint(coordinate: fix, at: instant)) else { return }
        // Su disco ogni venti punti, non a ogni punto: sono ~40 minuti di
        // navigazione, e il file lo rilegge anche il widget.
        guard track.points.count - savedTrackPoints >= 20 else { return }
        persistTrack()
    }

    /// Scrive la traccia adesso. Da chiamare anche quando l'app va in secondo piano,
    /// se no gli ultimi punti si perdono al primo riavvio.
    func persistTrack() {
        guard !isDemo, !isEphemeral else { return }
        savedTrackPoints = track.points.count
        try? TrackArchive.save(track)
    }

    /// Le miglia percorse dalla crociera in corso: quelle **vere** se la rotta è
    /// stata registrata, quelle degli orari se no.
    var nauticalMiles: Double {
        track.isEmpty ? (voyage.map { LoggedVoyage.sailed($0, upTo: now).nauticalMiles } ?? 0)
                      : track.nauticalMiles
    }

    /// Chiude i conti su una crociera che sta per essere sostituita.
    ///
    /// Alla fine del viaggio si archivia tutto l'itinerario, non solo la parte già
    /// passata: se la crociera è finita davvero, l'ultimo scalo lo hai toccato.
    private func closeOut(_ outgoing: Voyage?) {
        guard let outgoing, !isDemo, !isEphemeral else { return }
        let completed = outgoing.moment(at: now) == .completed
        var entry = LoggedVoyage.sailed(outgoing, upTo: completed ? .distantFuture : now)
        // La rotta percorsa entra nel diario **alleggerita**: una settimana di punti
        // ogni due minuti fa cinquemila righe, e nel diario ci restano per sempre.
        // Semplificata la forma è la stessa e le righe sono poche centinaia.
        if !track.isEmpty {
            entry.track = track.simplified()
            entry.nauticalMiles = track.nauticalMiles
        }
        logbook.record(entry)
        try? LogbookArchive.save(logbook)
        track = Track()
        savedTrackPoints = 0
        TrackArchive.clear()
    }

    /// Cancella una crociera dal diario. Esiste perché una crociera inserita per
    /// sbaglio deve poter uscire: un diario che non si può correggere si smette di
    /// guardare.
    func forget(_ entry: LoggedVoyage) {
        logbook.voyages.removeAll { $0.id == entry.id }
        guard !isEphemeral else { return }
        try? LogbookArchive.save(logbook)
    }

    // MARK: Cose derivate

    var moment: Voyage.Moment? { voyage?.moment(at: now) }
    var focus: Voyage.Focus? { voyage?.focus(at: now) }
    var today: VoyageDay? { voyage?.currentDay(at: now) }
    var days: [VoyageDay] { voyage?.days(at: now) ?? [] }

    /// Da quanto prima della salita a bordo si accende la vista normale.
    ///
    /// Prima di questa soglia i countdown in ore, la carta e le metriche non servono
    /// a niente: la crociera è un'attesa, non un'operazione. Dodici ore è la sera
    /// prima, quando si prepara la valigia e l'app torna a essere uno strumento.
    static let normalViewLead: TimeInterval = 12 * 3600

    /// Vero finché la crociera è ancora un'attesa e non un viaggio in corso.
    var isAwaitingDeparture: Bool {
        guard case .beforeVoyage(let call) = moment else { return false }
        return call.arrival.timeIntervalSince(now) > Self.normalViewLead
    }

    /// Vero quando la nave è ferma in banchina.
    var isInPort: Bool {
        if case .inPort = moment { return true }
        return false
    }

    /// Il colore che guida la schermata. Cambia col contesto, ma non porta mai da
    /// solo il significato: accanto c'è sempre un glifo e una parola.
    var accent: Color { isInPort ? Palette.ashore : Palette.underway }

    /// Lo sfondo della schermata, coerente con l'accento.
    /// Il fondo della schermata: segue l'ora **di bordo**, non quella del telefono.
    /// Uno sfondo che si accende quando il telefono dice mezzogiorno mentre a bordo
    /// sono le sei sarebbe la stessa bugia dei countdown sbagliati.
    var background: LinearGradient {
        Palette.background(hour: shipHour, inPort: isInPort)
    }

    /// L'ora di bordo come numero decimale, per il ciclo del giorno.
    var shipHour: Double {
        guard let clock = voyage?.clock else { return 21 }   // senza crociera: sera
        let parts = clock.calendar(at: now).dateComponents([.hour, .minute], from: now)
        return Double(parts.hour ?? 21) + Double(parts.minute ?? 0) / 60
    }

    /// La posizione dedotta dagli orari. Il GPS di bordo, quando c'è, la sostituisce.
    var scheduledFix: ShipFix? { voyage?.scheduledFix(at: now) }

    /// Il fuso di uno scalo, cercato nell'elenco dei porti.
    ///
    /// Si sceglie il candidato **più vicino alle coordinate salvate**, non il primo
    /// col nome giusto: St John's è ad Antigua e a Terranova, e prendere quello
    /// sbagliato sposterebbe l'ora di bordo di tre ore e mezza.
    private static func portZone(for call: PortCall) -> String? {
        let candidates = PortGazetteer.shared.candidates(call.name)
        guard !candidates.isEmpty else { return nil }
        let nearest = candidates.min {
            Geo.nauticalMiles(from: call.coordinate, to: $0.coordinate)
                < Geo.nauticalMiles(from: call.coordinate, to: $1.coordinate)
        }
        guard let nearest,
              Geo.nauticalMiles(from: call.coordinate, to: nearest.coordinate) < 60
        else { return nil }
        return nearest.timeZoneIdentifier
    }

    /// La crociera con i fusi riempiti e l'orologio riallineato agli scali.
    private static func reconciled(_ voyage: Voyage?) -> Voyage? {
        voyage?.reconciled(portZone)
    }

    // MARK: Modifiche

    func replace(with voyage: Voyage?) {
        if self.voyage?.id != voyage?.id { closeOut(self.voyage) }
        var stamped = Self.reconciled(voyage)
        stamped?.updatedAt = Date()
        self.voyage = stamped
        // Una crociera messa dentro a mano è vera anche se prima c'era una prova.
        isDemo = false
        loggedCallCount = 0
        recordProgress(force: true)
        persist()
    }

    /// Corregge gli orari di uno scalo dopo un annuncio di bordo. La correzione
    /// diventa `userEdited`, cioè vince su qualunque orario pubblicato.
    func amend(_ call: PortCall) {
        guard var voyage, let index = voyage.calls.firstIndex(where: { $0.id == call.id }) else { return }
        var amended = call
        amended.scheduleOrigin = .userEdited
        voyage.calls[index] = amended
        voyage.calls.sort { $0.arrival < $1.arrival }
        voyage.updatedAt = Date()
        // Spostare un orario può spostare la notte in cui gira l'orologio: la
        // scaletta va rifatta, se no resta quella di prima della correzione.
        self.voyage = Self.reconciled(voyage)
        persist()
    }

    // MARK: Persistenza
    //
    // Il file vive in `VoyageArchive`, dentro il contenitore condiviso, così anche
    // widget e Live Activity leggono la stessa crociera.

    private func persist() {
        guard !isEphemeral else { return }
        do {
            try VoyageArchive.save(voyage)
            // I widget vanno svegliati: hanno una copia vecchia della crociera.
            WidgetCentre.reload()
        } catch {
            // Fallire il salvataggio non deve far cadere l'app: la crociera resta
            // in memoria e il prossimo salvataggio riproverà.
            assertionFailure("Salvataggio della crociera non riuscito: \(error)")
        }
    }
}

extension VoyageStore {
    /// Carica uno scenario di prova da riga di comando, per pilotare il simulatore
    /// senza dover digitare un itinerario a ogni avvio:
    /// `-sample inPort`, `atSea`, `beforeBoarding`, `farFromBoarding`, `imminent`.
    ///
    /// **`-sample deviceTest` è diverso dagli altri**: scrive la crociera
    /// nell'archivio condiviso invece di tenerla in memoria. Serve per provare
    /// widget e Live Activity, che girano in un altro processo e leggono da lì — con
    /// uno scenario solo in memoria vedrebbero un widget vuoto. La crociera vera
    /// viene messa da parte prima, e `-sampleRestore` la rimette.
    static func debugScenario() -> SampleVoyage.Scenario? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-sampleRestore") {
            VoyageArchive.restore()
            return nil
        }

        guard let flag = arguments.firstIndex(of: "-sample"),
              arguments.index(after: flag) < arguments.endIndex
        else { return nil }

        let scenario: SampleVoyage.Scenario?
        switch arguments[arguments.index(after: flag)] {
        case "inPort": scenario = SampleVoyage.inPort()
        case "atSea": scenario = SampleVoyage.atSea()
        case "beforeBoarding": scenario = SampleVoyage.beforeBoarding()
        case "farFromBoarding": scenario = SampleVoyage.farFromBoarding()
        case "imminent": scenario = SampleVoyage.allAboardImminent()
        case "deviceTest": scenario = SampleVoyage.deviceTest()
        default: scenario = nil
        }

        if arguments.contains("deviceTest"), let scenario {
            try? VoyageArchive.backUp()
            try? VoyageArchive.save(scenario.voyage)
            WidgetCentre.reload()
        }
        return scenario
        #else
        return nil
        #endif
    }
}

#if DEBUG
extension VoyageStore {
    /// Store per le anteprime, senza toccare il disco.
    private static func preview(_ scenario: SampleVoyage.Scenario) -> VoyageStore {
        VoyageStore(voyage: scenario.voyage, timeOffset: scenario.timeOffset, autoload: false)
    }
    static var preview: VoyageStore { preview(SampleVoyage.inPort()) }
    static var previewAtSea: VoyageStore { preview(SampleVoyage.atSea()) }
    static var previewImminent: VoyageStore { preview(SampleVoyage.allAboardImminent()) }
    static var previewEmpty: VoyageStore { VoyageStore(voyage: nil, autoload: false) }
}
#endif
