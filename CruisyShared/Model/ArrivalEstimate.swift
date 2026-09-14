import Foundation

/// Quando arriverà la nave, secondo l'andatura delle ultime ore.
///
/// **Non sostituisce l'orario pubblicato, e non tocca il countdown.** È la regola che
/// regge tutta l'app: una stima ottimistica è il modo più semplice di perdere la nave.
/// Serve a una cosa sola, chiesta da Matteo il 4 settembre 2026: **avvisare quando le
/// due cose non tornano**, perché un arrivo in ritardo di un'ora sposta anche l'all
/// aboard di quello scalo, e saperlo in mare è meglio che scoprirlo in banchina.
///
/// Tre scelte la rendono prudente, cioè portata a tacere piuttosto che ad allarmare:
///
/// - la distanza che resta è **in linea retta** fino al porto. La nave farà più strada,
///   quindi la stima è sempre un po' in anticipo sul vero: se anche così risulta in
///   ritardo, il ritardo c'è;
/// - la velocità è la **media delle ultime tre ore** di traccia, non quella istantanea
///   del GPS, che oscilla a ogni onda e scende a zero quando la nave rallenta per il
///   pilota;
/// - si stima solo **a meno di 12 ore dall'arrivo**. Più lontano, una nave che va piano
///   di notte per risparmiare carburante e accelera all'alba risulterebbe in ritardo
///   senza esserlo.
public struct ArrivalEstimate: Equatable, Sendable {

    /// L'arrivo che la nave farebbe tenendo l'andatura media delle ultime ore.
    public let expected: Date
    /// L'arrivo dell'itinerario.
    public let published: Date
    /// L'andatura media usata per la stima, in nodi.
    public let averageKnots: Double

    /// Di quanto la stima supera l'orario pubblicato. Negativo = in anticipo.
    public var delay: TimeInterval { expected.timeIntervalSince(published) }

    /// Da quale ritardo vale la pena dirlo. Sotto l'ora, una nave recupera quasi sempre.
    public static let threshold: TimeInterval = 60 * 60

    /// Vero quando il ritardo stimato è abbastanza grande da avvisare.
    public var isLate: Bool { delay >= Self.threshold }

    /// Quanta traccia recente si usa per la media.
    static let averagingWindow: TimeInterval = 3 * 3600
    /// Sotto quest'ampiezza la media non è affidabile.
    static let minimumSpan: TimeInterval = 90 * 60
    /// Oltre questo tempo dall'arrivo non si stima.
    static let horizon: TimeInterval = 12 * 3600
    /// L'ultimo punto dev'essere recente: una traccia ferma da un'ora non dice dove
    /// si è adesso.
    static let freshness: TimeInterval = 30 * 60
    /// Sotto quest'andatura la nave è ferma o quasi, e dividere per quasi zero darebbe
    /// ritardi di giorni. Una nave ferma in mare aspetta qualcosa; non si stima.
    static let minimumKnots: Double = 2

    public init(expected: Date, published: Date, averageKnots: Double) {
        self.expected = expected
        self.published = published
        self.averageKnots = averageKnots
    }

    /// La stima verso `destination`, o nulla se i dati non bastano a farla onesta.
    public static func estimate(track: Track, destination: PortCall, now: Date) -> ArrivalEstimate? {
        let untilArrival = destination.arrival.timeIntervalSince(now)
        guard untilArrival > 0, untilArrival <= horizon else { return nil }

        let recent = track.clipped(from: now.addingTimeInterval(-averagingWindow), to: now)
        guard let first = recent.first, let last = recent.last,
              now.timeIntervalSince(last.at) <= freshness
        else { return nil }

        let span = last.at.timeIntervalSince(first.at)
        guard span >= minimumSpan else { return nil }

        let knots = recent.nauticalMiles / (span / 3600)
        guard knots >= minimumKnots else { return nil }

        let remaining = Geo.nauticalMiles(from: last.coordinate, to: destination.coordinate)
        let expected = last.at.addingTimeInterval(remaining / knots * 3600)
        return ArrivalEstimate(expected: expected, published: destination.arrival, averageKnots: knots)
    }
}
