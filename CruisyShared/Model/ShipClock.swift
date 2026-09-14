import Foundation

/// L'ora di bordo.
///
/// Non è un dettaglio di formattazione: le navi tengono la propria ora e non sempre
/// la allineano al porto in cui attraccano, mentre il telefono si riallinea da solo
/// appena aggancia la rete locale. Se l'app mostrasse l'all aboard nell'ora del
/// telefono, in un porto disallineato direbbe l'orario sbagliato — e chi la usa
/// perde la nave.
///
/// Quindi: tutti gli istanti sono in UTC, e questo tipo è l'unica cosa che decide
/// come si scrivono a schermo.
///
/// ## Perché è una scaletta e non un numero
///
/// Prima qui c'era un solo scarto per tutta la crociera. Non è come vanno le cose:
/// la nave **sposta l'orologio durante la traversata**, quasi sempre alle 02:00, e
/// chi dorme si sveglia con un'ora diversa da quella con cui è andato a letto. Un
/// solo scarto avrebbe raccontato bene un giorno solo, e mentito tutti gli altri.
///
/// Le regole, come le tengono le compagnie:
///
/// - **In porto** vale l'ora civile di quel porto.
/// - **L'ultimo giorno di mare prima di uno scalo è già sull'ora di quello scalo**:
///   il cambio scatta alle 02:00 della notte che apre quel giorno, non della notte
///   prima dell'attracco. Ci si sveglia già allineati a dove si arriverà.
/// - **I giorni di mare precedenti** stanno in **ora nautica**, cioè lo scarto del
///   fuso che compete alla longitudine dove ci si trova, e cambiano anche loro alle
///   02:00 quando si scavalca un meridiano di zona.
///
/// Gli scarti sono numeri e non fusi geografici: una nave adotta uno scarto, non le
/// leggi di un paese, e non fa l'ora legale a metà oceano. La legge del paese conta
/// una volta sola, quando si ricava lo scarto del porto alla data dello scalo.
public struct ShipClock: Codable, Hashable, Sendable {

    public enum Source: String, Codable, Sendable {
        /// Ricavata dal fuso civile di uno scalo.
        case portTimeZone
        /// Ora nautica, dalla longitudine: in mezzo a una traversata lunga.
        case nautical
        /// Impostata a mano da chi è a bordo, che ha sentito l'annuncio.
        case manual
    }

    /// Un cambio d'orologio: da questo istante in poi la nave tiene questo scarto.
    public struct Change: Codable, Hashable, Sendable {
        /// L'istante del cambio. Nella pratica le 02:00 di bordo, con l'orologio
        /// ancora sullo scarto vecchio.
        public var at: Date
        public var secondsFromGMT: Int
        public var source: Source

        public init(at: Date, secondsFromGMT: Int, source: Source) {
            self.at = at
            self.secondsFromGMT = secondsFromGMT
            self.source = source
        }
    }

    /// I cambi in ordine di tempo. **Non è mai vuota**: la prima voce vale da sempre,
    /// così qualunque istante — anche prima dell'imbarco — ha una risposta.
    public private(set) var changes: [Change]

    public init(changes: [Change]) {
        let ordered = changes.sorted { $0.at < $1.at }
        // Due cambi allo stesso scarto sono un cambio solo: senza questa potatura
        // l'avviso "stanotte l'orologio si sposta" comparirebbe per notti in cui non
        // si sposta niente.
        var pruned: [Change] = []
        for change in ordered where pruned.last?.secondsFromGMT != change.secondsFromGMT {
            pruned.append(change)
        }
        self.changes = pruned.isEmpty
            ? [Change(at: .distantPast, secondsFromGMT: 0, source: .portTimeZone)]
            : [Change(at: .distantPast, secondsFromGMT: pruned[0].secondsFromGMT,
                      source: pruned[0].source)] + pruned.dropFirst()
    }

    /// Un orologio che non cambia mai: quello di chi lo imposta a mano, e quello
    /// delle crociere salvate prima che questa scaletta esistesse.
    public init(secondsFromGMT: Int, source: Source = .portTimeZone) {
        self.changes = [Change(at: .distantPast, secondsFromGMT: secondsFromGMT,
                               source: source)]
    }

    // MARK: Leggere l'ora

    /// Il cambio in vigore a una data.
    public func change(at date: Date) -> Change {
        var current = changes[0]
        for change in changes where change.at <= date { current = change }
        return current
    }

    /// Scarto da UTC in secondi, all'istante dato.
    public func secondsFromGMT(at date: Date) -> Int { change(at: date).secondsFromGMT }

    public func source(at date: Date) -> Source { change(at: date).source }

    /// Fuso fisso corrispondente all'istante dato. Fisso e non geografico: l'ora di
    /// bordo non fa l'ora legale e non segue le regole di un paese.
    public func timeZone(at date: Date) -> TimeZone {
        TimeZone(secondsFromGMT: secondsFromGMT(at: date)) ?? .gmt
    }

    /// Il prossimo spostamento d'orologio dopo una data, se ce n'è uno.
    ///
    /// È quello che serve per avvisare: un cambio d'orologio non annunciato è uno dei
    /// modi più comuni di perdere la nave.
    public func nextChange(after date: Date) -> Change? {
        changes.first { $0.at > date }
    }

    /// Di quanto si sposta l'orologio a un cambio, in secondi. Positivo = avanti.
    public func shift(at change: Change) -> Int {
        guard let index = changes.firstIndex(where: { $0.at == change.at }), index > 0
        else { return 0 }
        return change.secondsFromGMT - changes[index - 1].secondsFromGMT
    }

    /// L'ora di un cambio letta **con l'orologio di prima**.
    ///
    /// Sono "le due di notte" di chi va a dormire, non l'ora che quell'istante avrà
    /// un attimo dopo. Leggerlo con l'orologio nuovo darebbe l'una o le tre, e
    /// l'avviso annuncerebbe il cambio a un'ora a cui non succede niente.
    ///
    /// La prima versione ci arrivava togliendo un secondo all'istante: usciva
    /// "01:59", che è esattamente il genere di dettaglio che fa dubitare di tutto
    /// il resto.
    public func timeBeforeChange(_ change: Change, locale: Locale = .current) -> String {
        let before = change.secondsFromGMT - shift(at: change)
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(secondsFromGMT: before) ?? .gmt
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f.string(from: change.at)
    }

    /// Etichetta dello scarto, es. "UTC−4" oppure "UTC+5:30".
    public func offsetLabel(at date: Date) -> String {
        Self.offsetLabel(secondsFromGMT: secondsFromGMT(at: date))
    }

    public static func offsetLabel(secondsFromGMT: Int) -> String {
        let total = abs(secondsFromGMT)
        let hours = total / 3600, minutes = (total % 3600) / 60
        let sign = secondsFromGMT < 0 ? "−" : "+"
        return minutes == 0 ? "UTC\(sign)\(hours)" : "UTC\(sign)\(hours):\(String(format: "%02d", minutes))"
    }

    /// Vero quando il telefono e la nave segnano la stessa ora: in quel caso non
    /// c'è niente da spiegare all'utente e la striscia di avviso resta nascosta.
    public func matchesDevice(at date: Date, device: TimeZone = .current) -> Bool {
        device.secondsFromGMT(for: date) == secondsFromGMT(at: date)
    }

    /// Di quanto il telefono è avanti o indietro rispetto alla nave, in secondi.
    public func deviceDrift(at date: Date, device: TimeZone = .current) -> Int {
        device.secondsFromGMT(for: date) - secondsFromGMT(at: date)
    }

    /// Formattatore agganciato all'ora di bordo di quell'istante.
    public func formatter(at date: Date,
                          dateStyle: DateFormatter.Style = .none,
                          timeStyle: DateFormatter.Style = .short,
                          locale: Locale = .current) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone(at: date)
        f.dateStyle = dateStyle
        f.timeStyle = timeStyle
        return f
    }

    /// L'ora di bordo scritta come "14:32".
    public func time(_ date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone(at: date)
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f.string(from: date)
    }

    /// Il giorno di bordo a cui appartiene un istante, cioè la mezzanotte di bordo.
    public func startOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(at: date)
        return calendar.startOfDay(for: date)
    }

    /// Un calendario che ragiona in ora di bordo a quella data.
    public func calendar(at date: Date) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(at: date)
        return calendar
    }

    // MARK: Persistenza
    //
    // Le crociere salvate prima della scaletta hanno `secondsFromGMT` e `source` in
    // cima all'oggetto. Vanno lette senza perdere niente, e senza chiedere all'utente
    // di reinserire l'itinerario: si trasformano in una scaletta con un cambio solo.

    private enum CodingKeys: String, CodingKey {
        case changes, secondsFromGMT, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let changes = try container.decodeIfPresent([Change].self, forKey: .changes) {
            self.init(changes: changes)
        } else {
            let seconds = try container.decode(Int.self, forKey: .secondsFromGMT)
            let source = try container.decodeIfPresent(Source.self, forKey: .source)
            self.init(secondsFromGMT: seconds, source: source ?? .portTimeZone)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changes, forKey: .changes)
        // Scritto anche nella forma vecchia: una versione precedente dell'app che
        // legge questo archivio trova comunque un orologio sensato invece di niente.
        try container.encode(changes[0].secondsFromGMT, forKey: .secondsFromGMT)
        try container.encode(changes[0].source, forKey: .source)
    }
}
