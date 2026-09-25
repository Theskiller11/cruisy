import Foundation
import Observation

/// Il diario di bordo in memoria, e il suo file.
///
/// Un porto entra nel diario quando ci sei arrivato, non quando lo cancelli dalla
/// crociera: se aspettassimo la fine del viaggio, sostituire l'itinerario a metà
/// rotta cancellerebbe metà diario. Chi decide **quando** guardare è `VoyageStore`,
/// che conosce l'orologio; qui c'è solo il diario e la regola per scriverlo.
@MainActor
@Observable
final class LogbookStore {

    private(set) var logbook: Logbook

    /// Quanti scali della crociera corrente sono già finiti nel diario. Serve solo
    /// a non riscrivere il file a ogni battito dell'orologio.
    private var loggedCallCount = 0

    /// Le crociere di prova: si vedono, ma non si scrivono mai nel file.
    private var samples: Set<UUID> = []

    /// Falso per anteprime e test: il diario resta in memoria.
    ///
    /// Senza questo, un'anteprima di SwiftUI che registra una crociera sovrascrive il
    /// diario vero di chi sta usando l'app. Non è teoria: è successo a un test, che
    /// ha cancellato l'archivio di un altro.
    private let persists: Bool

    init(persists: Bool = true) {
        self.persists = persists
        logbook = persists ? LogbookArchive.load() : Logbook()
    }

    /// Riporta nel diario la parte di crociera già percorsa.
    ///
    /// Si chiama spesso — a ogni battito e a ogni modifica — ma tocca il disco solo
    /// quando c'è davvero uno scalo in più da segnare.
    ///
    /// - Parameter writing: falso per gli scenari di prova, che si vedono nel diario
    ///   ma non devono sporcare le miglia di nessuno.
    func recordProgress(of voyage: Voyage, upTo now: Date, force: Bool = false, writing: Bool) {
        let entry = LoggedVoyage.sailed(voyage, upTo: now)
        guard force || entry.ports.count != loggedCallCount else { return }
        loggedCallCount = entry.ports.count
        logbook.record(entry)
        if writing { save() }
    }

    /// Ricomincia a contare gli scali: la crociera è cambiata.
    func startCounting() { loggedCallCount = 0 }

    /// Chiude i conti su una crociera che sta per essere sostituita.
    ///
    /// Alla fine del viaggio si archivia tutto l'itinerario, non solo la parte già
    /// passata: se la crociera è finita davvero, l'ultimo scalo lo hai toccato.
    /// La rotta percorsa entra **alleggerita**: una settimana di punti ogni due
    /// minuti fa cinquemila righe, e nel diario ci restano per sempre.
    func closeOut(_ voyage: Voyage, at now: Date, track: Track) {
        let completed = voyage.moment(at: now) == .completed
        var entry = LoggedVoyage.sailed(voyage, upTo: completed ? .distantFuture : now)
        if !track.isEmpty {
            entry.track = track.simplified()
            entry.nauticalMiles = track.nauticalMiles
        }
        logbook.record(entry)
        save()
    }

    /// Cancella una crociera dal diario. Esiste perché una crociera inserita per
    /// sbaglio deve poter uscire: un diario che non si può correggere si smette di
    /// guardare.
    func forget(_ entry: LoggedVoyage) {
        logbook.voyages.removeAll { $0.id == entry.id }
        save()
    }

    /// Toglie la rotta a una crociera e lascia il resto: miglia, porti, date.
    ///
    /// Per chi vuole il diario ma non vuole tenere, per sempre, dov'è passato
    /// punto per punto. Le miglia restano quelle già contate: sono un numero, non
    /// un posto.
    func forgetTrack(of entry: LoggedVoyage) {
        guard let index = logbook.voyages.firstIndex(where: { $0.id == entry.id }) else { return }
        logbook.voyages[index].track = nil
        save()
    }

    #if DEBUG
    /// Mette nel diario una crociera di prova, **solo in memoria**.
    func include(sample entry: LoggedVoyage) {
        samples.insert(entry.id)
        logbook.record(entry)
    }
    #endif

    private func save() {
        guard persists else { return }
        var written = logbook
        written.voyages.removeAll { samples.contains($0.id) }
        try? LogbookArchive.save(written)
    }
}
