import Foundation
import Observation

/// La rotta percorsa dalla crociera in corso, e il suo file.
///
/// Riceve i punti dal GPS e li passa a `Track`, che decide se valgono. Il filtro
/// sta nel modello e non qui, così vale allo stesso modo per il GPS in primo piano
/// e per quello in background.
@MainActor
@Observable
final class TrackRecorder {

    private(set) var track: Track

    /// Quanti punti c'erano l'ultima volta che si è scritto su disco.
    private var savedPointCount = 0

    /// Se i punti finiscono su disco. Falso per anteprime, test e scenari di prova:
    /// una crociera di collaudo non deve lasciare una traccia nell'archivio vero.
    var writesToDisk: Bool

    /// Ogni quanti punti nuovi si scrive: sono ~40 minuti di navigazione, e il file
    /// lo rilegge anche il widget, quindi non a ogni punto.
    static let pointsBetweenSaves = 20

    init(loadsFromDisk: Bool = true) {
        writesToDisk = loadsFromDisk
        track = loadsFromDisk ? TrackArchive.load() : Track()
        savedPointCount = track.points.count
    }

    /// Segna un punto, se porta informazione. Dice se l'ha segnato.
    @discardableResult
    func record(fix: Coordinate, at instant: Date) -> Bool {
        guard track.append(TrackPoint(coordinate: fix, at: instant)) else { return false }
        if track.points.count - savedPointCount >= Self.pointsBetweenSaves { persist() }
        return true
    }

    /// Scrive la traccia adesso. Da chiamare anche quando l'app va in secondo piano,
    /// se no gli ultimi punti si perdono al primo riavvio.
    func persist() {
        guard writesToDisk else { return }
        savedPointCount = track.points.count
        try? TrackArchive.save(track)
    }

    /// Butta la traccia: la crociera è finita o è stata sostituita.
    func reset() {
        track = Track()
        savedPointCount = 0
        if writesToDisk { TrackArchive.clear() }
    }
}
