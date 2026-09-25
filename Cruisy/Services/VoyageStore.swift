import Foundation
import Observation

/// La crociera in corso e l'istante su cui è impaginata l'app.
///
/// Fino al 14 settembre 2026 qui dentro stavano anche il diario, la traccia e le
/// preferenze: sei responsabilità in un oggetto. Adesso ognuna ha il suo tipo —
/// `LogbookStore`, `TrackRecorder`, `Preferences` — e questo store fa da
/// coordinatore per le due cose che dipendono dall'orologio della crociera: quando
/// uno scalo entra nel diario, e quando una crociera sostituita va archiviata.
///
/// `now` si aggiorna ogni trenta secondi, non al secondo. I secondi servono solo
/// dentro il countdown, che li rende da sé con `TimelineView`: far ridisegnare
/// l'intera schermata una volta al secondo costerebbe batteria a bordo, dove
/// ricaricare non è sempre comodo.
@MainActor
@Observable
final class VoyageStore {

    // MARK: Stato

    private(set) var voyage: Voyage?
    /// L'istante su cui è impaginata la schermata.
    private(set) var now: Date = .now
    /// Scarto fra l'ora vera e il punto di osservazione. Zero in produzione; lo usa
    /// solo il collaudo, per mettersi a venti minuti dall'all aboard senza aspettare.
    private(set) var timeOffset: TimeInterval = 0

    /// Il diario, che sopravvive alle crociere.
    let logbook: LogbookStore
    /// La rotta davvero percorsa.
    let recorder: TrackRecorder

    /// Vero quando la crociera in corso è uno scenario di collaudo. Il diario la
    /// mostra — se no in DEBUG sarebbe sempre vuoto — ma non la scrive su disco:
    /// i dati di prova non devono sporcare le miglia di nessuno.
    private var isDemo = false
    /// Uno store che non deve toccare il disco: anteprime e test.
    private let isEphemeral: Bool

    private var ticker: Timer?

    // MARK: Ciclo di vita

    /// - Parameters:
    ///   - autoload: falso per anteprime e test, che non devono né leggere né
    ///     scrivere l'archivio vero.
    ///   - logbook, recorder: i pezzi coordinati. Se non passati, se ne creano di
    ///     coerenti con `autoload`.
    init(voyage: Voyage? = nil, now: Date = .now, timeOffset: TimeInterval = 0,
         autoload: Bool = true, logbook: LogbookStore? = nil, recorder: TrackRecorder? = nil) {
        self.isEphemeral = !autoload
        self.logbook = logbook ?? LogbookStore(persists: autoload)
        self.recorder = recorder ?? TrackRecorder(loadsFromDisk: autoload)
        self.timeOffset = timeOffset
        self.now = now.addingTimeInterval(timeOffset)
        if let voyage {
            self.voyage = voyage
        } else if autoload, let scenario = Self.debugScenario() {
            self.voyage = scenario.voyage
            self.isDemo = true
            #if DEBUG
            // Una crociera già finita, perché la pagina di una crociera conclusa
            // si possa vedere: quella di prova è sempre in corso. `-diarioVuoto` la
            // toglie, per vedere il diario ancora bianco prima dell'imbarco.
            if !ProcessInfo.processInfo.arguments.contains("-diarioVuoto") {
                self.logbook.include(sample: SampleVoyage.pastCruise())
            }
            #endif
            self.timeOffset = scenario.timeOffset
            self.now = now.addingTimeInterval(scenario.timeOffset)
        } else if autoload {
            // Riconciliata al caricamento: una crociera salvata prima dei fusi
            // non ne ha nessuno, e senza questo l'ora di bordo non cambierebbe mai.
            self.voyage = Self.reconciled(VoyageArchive.load())
        }
        self.recorder.writesToDisk = writesToDisk
        recordProgress()
        startTicking()
    }

    // `isolated`: il timer vive sull'attore principale, e da un `deinit` non
    // isolato non si potrebbe nemmeno toccare.
    isolated deinit { ticker?.invalidate() }

    /// Quando quello che succede va scritto davvero.
    private var writesToDisk: Bool { !isDemo && !isEphemeral }

    /// Riallinea `now` ogni trenta secondi. Il passaggio fra porto e mare, o fra un
    /// giorno e l'altro, non ha bisogno di una precisione più fine.
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

    // MARK: Diario e rotta

    private func recordProgress(force: Bool = false) {
        guard let voyage else { return }
        logbook.recordProgress(of: voyage, upTo: now, force: force, writing: writesToDisk)
    }

    /// Segna un punto della rotta, se c'è una crociera da cui farsi misurare.
    func record(fix: Coordinate, at instant: Date) {
        guard voyage != nil, !isEphemeral else { return }
        recorder.record(fix: fix, at: instant)
    }

    /// Le miglia percorse dalla crociera in corso: quelle **vere** se la rotta è
    /// stata registrata, quelle degli orari se no.
    var nauticalMiles: Double {
        recorder.track.isEmpty
            ? (voyage.map { LoggedVoyage.sailed($0, upTo: now).nauticalMiles } ?? 0)
            : recorder.track.nauticalMiles
    }

    /// Chiude i conti su una crociera che sta per essere sostituita.
    private func closeOut(_ outgoing: Voyage?) {
        guard let outgoing, writesToDisk else { return }
        logbook.closeOut(outgoing, at: now, track: recorder.track)
        recorder.reset()
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

    /// L'ora di bordo come numero decimale, per il ciclo del giorno della scena.
    ///
    /// **Di bordo**, non del telefono: un cielo che si accende quando il telefono
    /// dice mezzogiorno mentre a bordo sono le sei sarebbe la stessa bugia dei
    /// countdown sbagliati.
    var shipHour: Double {
        #if DEBUG
        if let forced = DebugLaunch.hour { return forced }
        #endif
        guard let clock = voyage?.clock else { return 21 }   // senza crociera: sera
        let parts = clock.calendar(at: now).dateComponents([.hour, .minute], from: now)
        return Double(parts.hour ?? 21) + Double(parts.minute ?? 0) / 60
    }

    /// La posizione dedotta dagli orari. Il GPS di bordo, quando c'è, la sostituisce.
    var scheduledFix: ShipFix? { voyage?.scheduledFix(at: now) }

    /// La scheda della nave, se è nell'elenco: serve alla livrea e alla foto.
    var shipRecord: ShipRecord? {
        voyage.flatMap { ShipDirectory.shared.lookup($0.shipName) }
    }

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
        recorder.writesToDisk = writesToDisk
        logbook.startCounting()
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
