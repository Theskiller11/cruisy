import Foundation

/// La scheda dati di una nave.
struct ShipRecord: Equatable, Sendable, Identifiable {
    var name: String
    var imo: String
    var mmsi: String
    /// Stazza lorda in tonnellate.
    var tonnage: Double
    /// Lunghezza fuori tutto in metri.
    var length: Double
    var beam: Double
    /// Anno di consegna. Zero se ignoto.
    var year: Int
    var operatorName: String
    var flag: String
    /// Il nome del file su Wikimedia Commons, non un'immagine.
    ///
    /// Le foto **non** viaggiano nell'app: sono libere ma quasi tutte obbligano a
    /// citare l'autore, quindi si scaricano a richiesta e si mostrano col credito
    /// accanto. Qui c'è solo il riferimento per andarle a prendere.
    var imageFile: String

    var id: String { name }

    var hasMeasurements: Bool { tonnage > 0 || length > 0 }
}

/// L'elenco delle navi da crociera del mondo, dentro l'app.
///
/// Viene da **Wikidata, che è CC0** — pubblico dominio, nessuna attribuzione dovuta.
/// Sono fatti: stazza, lunghezza, numero IMO, anno di consegna. I fatti non si
/// possono monopolizzare, ed è la ragione per cui questa scheda si può impacchettare
/// mentre un piano dei ponti no.
///
/// Serve a una cosa sola: scrivi «Explora I» e il resto si riempie da sé.
/// L'elenco impacchettato **non è l'ultima parola**: Wikidata cresce, e una nave
/// varata dopo l'ultima compilazione non ci sarebbe. Quello che si impara a bordo
/// finisce in `ShipOverlay`, un file accanto alla crociera, e da lì in poi vale
/// quanto il resto.
final class ShipDirectory: @unchecked Sendable {

    private let byKey: [String: ShipRecord]
    private let keys: [String]
    /// Le navi imparate dopo la compilazione. Hanno la precedenza: se una scheda è
    /// stata aggiornata apposta, è perché quella nel bundle era vecchia o assente.
    private var learned: [String: ShipRecord] = [:]
    private let lock = NSLock()

    static let shared = ShipDirectory()

    private init() {
        guard let url = Bundle.main.url(forResource: "ships", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count > 12,
              Array(data[0..<4]) == Array("CRSH".utf8)
        else {
            assertionFailure("ships.bin mancante o in un formato inatteso")
            byKey = [:]; keys = []
            return
        }

        var table: [String: ShipRecord] = [:]
        data.withUnsafeBytes { raw in
            let count = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            var offset = 12
            table.reserveCapacity(count)

            func string() -> String {
                let length = Int(raw[offset]); offset += 1
                defer { offset += length }
                return String(decoding: raw[offset..<(offset + length)], as: UTF8.self)
            }

            for _ in 0..<count {
                let key = string()
                let tonnage = Double(raw.loadUnaligned(fromByteOffset: offset, as: Float32.self))
                let length = Double(raw.loadUnaligned(fromByteOffset: offset + 4, as: Float32.self))
                let beam = Double(raw.loadUnaligned(fromByteOffset: offset + 8, as: Float32.self))
                let year = Int(raw.loadUnaligned(fromByteOffset: offset + 12, as: UInt16.self))
                offset += 14

                table[key] = ShipRecord(
                    name: string(), imo: string(), mmsi: string(),
                    tonnage: tonnage, length: length, beam: beam, year: year,
                    operatorName: string(), flag: string(), imageFile: string())
            }
        }
        byKey = table
        keys = table.keys.sorted()
    }

    var count: Int { byKey.count }

    // MARK: Quello che si impara dopo

    /// Aggiunge o aggiorna una nave, e la scrive su disco.
    func learn(_ record: ShipRecord) {
        let key = Self.fold(record.name)
        guard key.count >= 3 else { return }
        lock.lock()
        learned[key] = record
        let snapshot = learned
        lock.unlock()
        ShipOverlay.save(snapshot)
    }

    /// Rilegge dal disco quello che era già stato imparato. Da chiamare all'avvio.
    func loadLearned() {
        let stored = ShipOverlay.load()
        lock.lock()
        learned = stored
        lock.unlock()
    }

    private func known(_ key: String) -> ShipRecord? {
        lock.lock()
        defer { lock.unlock() }
        return learned[key] ?? byKey[key]
    }

    /// Deve restare identica alla funzione che ha costruito `ships.bin`.
    static func fold(_ text: String) -> String {
        let stripped = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let cleaned = stripped.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Cerca una nave per nome, con la tolleranza che serve a chi digita.
    func lookup(_ rawName: String) -> ShipRecord? {
        let folded = Self.fold(rawName)
        guard folded.count >= 3 else { return nil }
        if let hit = known(folded) { return hit }

        // "MSC Seaside (2017)" o "Costa Toscana – Costa Crociere": si prova anche
        // il solo pezzo iniziale.
        let words = folded.split(separator: " ").map(String.init)
        if words.count > 1 {
            for length in stride(from: words.count - 1, through: 2, by: -1) {
                let prefix = words.prefix(length).joined(separator: " ")
                if let hit = known(prefix) { return hit }
            }
        }
        return nil
    }

    /// Suggerimenti mentre si digita.
    func suggestions(for text: String, limit: Int = 8) -> [ShipRecord] {
        let folded = Self.fold(text)
        guard folded.count >= 2 else { return [] }
        var results: [ShipRecord] = []
        lock.lock()
        let extra = learned
        lock.unlock()
        // Le navi imparate vengono prima: se sei andato a cercarle apposta, sono
        // quelle che ti interessano.
        for (key, record) in extra where key.hasPrefix(folded) {
            results.append(record)
            if results.count >= limit { break }
        }
        for key in keys where key.hasPrefix(folded) && extra[key] == nil {
            if let record = byKey[key] { results.append(record) }
            if results.count >= limit { break }
        }
        // Se il prefisso non basta, si allarga a chi lo contiene: "seaside" deve
        // pescare "MSC Seaside".
        if results.isEmpty {
            for key in keys where key.contains(folded) {
                if let record = byKey[key] { results.append(record) }
                if results.count >= limit { break }
            }
        }
        return results
    }
}
