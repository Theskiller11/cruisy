import Foundation
import ActivityKit

/// Ciò che la Live Activity mostra sulla schermata di blocco e nella Dynamic Island.
///
/// Lo stato porta due date e non un tempo residuo: le cifre le conta il sistema, e
/// un "mancano 2:58" congelato al momento dell'invio sarebbe sbagliato un secondo dopo.
public struct AllAboardAttributes: ActivityAttributes {

    /// A che cosa si sta contando. Decide anche il colore: ambra in porto, verde
    /// acqua in navigazione — lo stesso codice dell'app, così l'attività si legge
    /// come una continuazione della schermata Oggi e non come un'altra cosa.
    public enum Kind: String, Codable, Hashable, Sendable {
        case allAboard, arrival

        public var isAtSea: Bool { self == .arrival }
    }

    public struct ContentState: Codable, Hashable {
        public var start: Date
        public var target: Date
        public var origin: CountdownOrigin
        public var kind: Kind
        /// Miglia che restano al prossimo porto.
        ///
        /// Congelata fra un aggiornamento e l'altro: un'attività in tempo reale non
        /// ricalcola da sé, sa solo far scorrere le date. È un ordine di grandezza,
        /// non una lettura al miglio — e a bordo va benissimo così.
        public var milesRemaining: Double?

        public init(start: Date, target: Date, origin: CountdownOrigin,
                    kind: Kind = .allAboard, milesRemaining: Double? = nil) {
            self.start = start
            self.target = target
            self.origin = origin
            self.kind = kind
            self.milesRemaining = milesRemaining
        }

        public var countdown: Countdown {
            Countdown(start: start, target: target, origin: origin)
        }

        public var range: ClosedRange<Date> { start...target }
    }

    public var portName: String
    public var shipName: String
    /// L'orario dell'all aboard già scritto in ora di bordo: la Live Activity non ha
    /// modo di sapere quale sia l'ora della nave, e ricalcolarla lì sarebbe una
    /// seconda occasione di sbagliarla.
    public var allAboardLabel: String
    public var berthLabel: String?

    public init(portName: String, shipName: String, allAboardLabel: String, berthLabel: String? = nil) {
        self.portName = portName
        self.shipName = shipName
        self.allAboardLabel = allAboardLabel
        self.berthLabel = berthLabel
    }
}
