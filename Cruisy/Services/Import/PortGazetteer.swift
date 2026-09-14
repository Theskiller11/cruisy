import Foundation

/// Un porto trovato nell'elenco.
struct PortMatch: Equatable, Sendable, Identifiable {
    let name: String
    let country: String
    let coordinate: Coordinate
    /// Il fuso civile del porto, es. `America/Santo_Domingo`.
    ///
    /// Serve all'ora di bordo: la nave sposta l'orologio sull'ora del porto dove sta
    /// andando, e senza questo l'app dovrebbe indovinarla dalla longitudine. È cucito
    /// dentro `ports.bin` da `scripts/build-port-timezones.py`, quindi resta
    /// disponibile senza rete — che è tutto il punto, in mezzo all'oceano.
    var timeZoneIdentifier: String?
    /// Quanto il nome cercato somigliava a quello trovato, da 0 a 1. Sotto 1 vuol
    /// dire che è stata una somiglianza, non un'uguaglianza.
    var confidence: Double

    var id: String { "\(name)|\(coordinate.latitude),\(coordinate.longitude)" }
    var subtitle: String { country.isEmpty ? Format.coordinate(coordinate) : country }
}

/// L'elenco dei porti del mondo, con le coordinate, dentro l'app.
///
/// Messo insieme da due fonti aperte: il **World Port Index** della NGA statunitense
/// (opera del governo USA, pubblico dominio) e le località con funzione portuale di
/// **UN/LOCODE**. Più una tabella di alias scritta a mano, perché le compagnie
/// scrivono "Santorini" dove il porto si chiama Thira.
///
/// Restituisce **tutti** i candidati, non il primo che capita. Su 15.000 chiavi ce ne
/// sono 632 ambigue — St John's è ad Antigua e a Terranova, Georgetown in cinque posti
/// diversi — e scegliere in silenzio significa mettere la nave dall'altra parte
/// dell'oceano senza dirlo. Chi sceglie è `disambiguate(_:)`, guardando dove sono gli
/// altri scali della crociera.
final class PortGazetteer: @unchecked Sendable {

    private let candidatesByKey: [String: [PortMatch]]
    private let keys: [String]

    static let shared = PortGazetteer()

    private init() {
        guard let url = Bundle.main.url(forResource: "ports", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count > 14,
              Array(data[0..<4]) == Array("CRPG".utf8)
        else {
            assertionFailure("ports.bin mancante o in un formato inatteso")
            candidatesByKey = [:]; keys = []
            return
        }

        var table: [String: [PortMatch]] = [:]
        data.withUnsafeBytes { raw in
            let version = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt16.self))
            let keyCount = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            var offset = 12
            table.reserveCapacity(keyCount)

            func string(_ length: Int) -> String {
                defer { offset += length }
                return String(decoding: raw[offset..<(offset + length)], as: UTF8.self)
            }

            // Dalla versione 3 i fusi stanno in una tabella in testa e ogni porto ne
            // porta l'indice: 382 nomi scritti una volta invece di uno per porto,
            // cioè 36 KB in più invece di 400.
            var zones: [String] = []
            if version >= 3 {
                let zoneCount = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                offset += 2
                zones.reserveCapacity(zoneCount)
                for _ in 0..<zoneCount {
                    let length = Int(raw[offset]); offset += 1
                    zones.append(string(length))
                }
            }

            for _ in 0..<keyCount {
                let keyLength = Int(raw[offset]); offset += 1
                let key = string(keyLength)
                let groupCount = Int(raw[offset]); offset += 1

                var group: [PortMatch] = []
                group.reserveCapacity(groupCount)
                for _ in 0..<groupCount {
                    let lat = Double(raw.loadUnaligned(fromByteOffset: offset, as: Float32.self))
                    let lon = Double(raw.loadUnaligned(fromByteOffset: offset + 4, as: Float32.self))
                    offset += 8
                    let nameLength = Int(raw[offset]); offset += 1
                    let name = string(nameLength)
                    let countryLength = Int(raw[offset]); offset += 1
                    let country = string(countryLength)

                    var zone: String?
                    if version >= 3 {
                        let index = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                        offset += 2
                        if zones.indices.contains(index) { zone = zones[index] }
                    }

                    group.append(PortMatch(name: name, country: country,
                                           coordinate: Coordinate(latitude: lat, longitude: lon),
                                           timeZoneIdentifier: zone,
                                           confidence: 1.0))
                }
                table[key] = group
            }
        }
        candidatesByKey = table
        keys = table.keys.sorted()
    }

    var count: Int { candidatesByKey.count }

    /// Normalizza un nome per il confronto. Deve restare identica alla funzione che
    /// ha costruito `ports.bin`.
    ///
    /// Gli apostrofi **spariscono** invece di diventare spazi. Sembra un dettaglio e
    /// invece era il baco: con l'apostrofo mappato a spazio, "St John's" e "St Johns"
    /// diventavano due chiavi diverse, e siccome esistono entrambe nei dati la ricerca
    /// trovava Terranova con confidenza piena mentre la crociera era ai Caraibi.
    static func fold(_ text: String) -> String {
        let stripped = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "\u{02BC}", with: "")
        let cleaned = stripped.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Tutti i porti che potrebbero corrispondere a un nome, dal più probabile in giù.
    func candidates(_ rawName: String) -> [PortMatch] {
        let folded = Self.fold(rawName)
        guard folded.count >= 3 else { return [] }

        if let group = candidatesByKey[folded] { return group }

        // "Charlotte Amalie (St. Thomas)", "Puerto Plata, Rep. Dominicana": ogni pezzo
        // separato da virgola o parentesi è un candidato a sé.
        for piece in rawName.split(whereSeparator: { ",()·–—/|".contains($0) }) {
            let key = Self.fold(String(piece))
            if key.count >= 3, let group = candidatesByKey[key] {
                return group.map { var m = $0; m.confidence = 0.9; return m }
            }
        }

        // Prefissi: "st johns antigua" -> "st johns".
        let words = folded.split(separator: " ").map(String.init)
        if words.count > 1 {
            for length in stride(from: words.count - 1, through: 1, by: -1) {
                let prefix = words.prefix(length).joined(separator: " ")
                if prefix.count >= 3, let group = candidatesByKey[prefix] {
                    return group.map { var m = $0; m.confidence = 0.8; return m }
                }
            }
        }

        // Ultima spiaggia: chiavi che contengono tutte le parole cercate. Prima ne
        // bastava una sola per accettarla in silenzio; adesso escono come candidati a
        // bassa confidenza, così passano comunque dalla disambiguazione e dal riesame.
        // Scandire tutte le chiavi a ogni nome costerebbe caro su un itinerario
        // lungo: ci si ferma appena si hanno abbastanza candidati, tanto oltre una
        // manciata non si disambigua più nulla.
        var loose: [PortMatch] = []
        for key in keys where words.allSatisfy({ key.contains($0) }) {
            loose.append(contentsOf: (candidatesByKey[key] ?? []).map {
                var m = $0; m.confidence = 0.55; return m
            })
            if loose.count >= 6 { break }
        }
        return loose
    }

    /// Il candidato migliore quando non c'è contesto per scegliere.
    func lookup(_ rawName: String) -> PortMatch? { candidates(rawName).first }

    /// Suggerimenti per il campo di ricerca del riesame.
    func suggestions(for text: String, limit: Int = 20) -> [PortMatch] {
        let folded = Self.fold(text)
        guard folded.count >= 2 else { return [] }
        var results: [PortMatch] = []
        for key in keys where key.hasPrefix(folded) {
            results.append(contentsOf: candidatesByKey[key] ?? [])
            if results.count >= limit { break }
        }
        return Array(results.prefix(limit))
    }
}
