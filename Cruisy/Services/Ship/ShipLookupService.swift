import Foundation
import Observation

/// Cerca una nave su Wikidata quando l'elenco impacchettato non ce l'ha.
///
/// `ships.bin` è una fotografia: una nave varata dopo l'ultima compilazione, o
/// aggiunta a Wikidata dopo, non ci sarebbe. Questo la va a prendere una alla volta.
///
/// **Una alla volta, e su richiesta.** Non si scarica l'intero elenco — sarebbero
/// megabyte per una riga che serve — e non parte da solo: l'app promette che niente
/// esce dal telefono se non lo decidi tu, e cercare un nome su un servizio di terzi
/// è comunque qualcosa che esce. Quindi c'è un pulsante, non un effetto collaterale.
///
/// Wikidata è **CC0**: i dati che tornano non hanno vincoli di attribuzione. Le foto
/// no, e infatti quelle continuano a passare da `ShipPhotoService`, col credito.
@Observable
@MainActor
final class ShipLookupService {

    enum Outcome: Equatable {
        case idle
        case searching
        case found(ShipRecord)
        case notFound
        case failed(String)
    }

    private(set) var outcome: Outcome = .idle

    private let session: URLSession
    private static let agent = "Cruisy/1.0 (app iOS; ricerca navi da Wikidata)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func reset() { outcome = .idle }

    /// Cerca la nave, e se la trova la insegna all'elenco.
    func search(_ rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3 else { return }
        outcome = .searching
        do {
            guard let id = try await candidate(for: name) else {
                outcome = .notFound
                return
            }
            guard let record = try await entity(id) else {
                outcome = .notFound
                return
            }
            ShipDirectory.shared.learn(record)
            outcome = .found(record)
        } catch is CancellationError {
            outcome = .idle
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    // MARK: Trovare la voce giusta

    /// Il primo risultato che sembra davvero una nave.
    ///
    /// Il filtro sulla descrizione serve: cercando «Explora III» il primo risultato
    /// è un videogioco del 1990, e senza controllo l'app mostrerebbe la stazza di
    /// un videogioco.
    private func candidate(for name: String) async throws -> String? {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "wbsearchentities"),
            .init(name: "search", value: name),
            .init(name: "language", value: "en"),
            .init(name: "uselang", value: "en"),
            .init(name: "limit", value: "8"),
            .init(name: "format", value: "json"),
        ]
        let json = try await get(components.url!)
        let results = json["search"] as? [[String: Any]] ?? []

        let marine = ["ship", "vessel", "liner", "cruise", "nave", "crociera", "transatlantico"]
        for result in results {
            let description = (result["description"] as? String ?? "").lowercased()
            guard marine.contains(where: description.contains) else { continue }
            if let id = result["id"] as? String { return id }
        }
        return nil
    }

    // MARK: Leggere la scheda

    private func entity(_ id: String) async throws -> ShipRecord? {
        guard var entity = try await entities([id])[id] else { return nil }
        // L'armatore è un'altra voce di Wikidata: il suo nome va chiesto a parte.
        if let operatorID = entity.operatorID {
            entity.record.operatorName = try await entities([operatorID])[operatorID]?.label ?? ""
        }
        if let flagID = entity.flagID {
            entity.record.flag = try await entities([flagID])[flagID]?.label ?? ""
        }
        return entity.record.name.isEmpty ? nil : entity.record
    }

    private struct Fetched {
        var record: ShipRecord
        var label: String
        var operatorID: String?
        var flagID: String?
    }

    private func entities(_ ids: [String]) async throws -> [String: Fetched] {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "wbgetentities"),
            .init(name: "ids", value: ids.joined(separator: "|")),
            .init(name: "props", value: "labels|claims"),
            // `mul` è la lingua dei nomi propri su Wikidata: senza, le navi recenti
            // tornano **senza nome**, in silenzio.
            .init(name: "languages", value: "mul|en|it"),
            .init(name: "format", value: "json"),
        ]
        let json = try await get(components.url!)
        guard let entities = json["entities"] as? [String: Any] else { return [:] }

        var result: [String: Fetched] = [:]
        for (id, raw) in entities {
            guard let entity = raw as? [String: Any] else { continue }
            let labels = entity["labels"] as? [String: Any] ?? [:]
            func label(_ code: String) -> String? {
                ((labels[code] as? [String: Any])?["value"] as? String)
            }
            let claims = entity["claims"] as? [String: Any] ?? [:]

            func value(_ property: String) -> Any? {
                guard let list = claims[property] as? [[String: Any]],
                      let snak = list.first?["mainsnak"] as? [String: Any],
                      let data = snak["datavalue"] as? [String: Any]
                else { return nil }
                return data["value"]
            }
            func string(_ property: String) -> String {
                value(property) as? String ?? ""
            }
            func quantity(_ property: String) -> Double {
                guard let amount = (value(property) as? [String: Any])?["amount"] as? String
                else { return 0 }
                return Double(amount.hasPrefix("+") ? String(amount.dropFirst()) : amount) ?? 0
            }
            func year(_ property: String) -> Int {
                guard let time = (value(property) as? [String: Any])?["time"] as? String,
                      time.count > 5 else { return 0 }
                return Int(time.dropFirst(time.hasPrefix("+") ? 1 : 0).prefix(4)) ?? 0
            }
            func reference(_ property: String) -> String? {
                (value(property) as? [String: Any])?["id"] as? String
            }

            // Il nome della nave è quello scritto sullo scafo: `mul` o inglese.
            // Armatore e bandiera si traducono, e l'app parla italiano.
            let shipName = label("mul") ?? label("en") ?? label("it") ?? ""
            let localised = label("it") ?? label("mul") ?? label("en") ?? ""

            result[id] = Fetched(
                record: ShipRecord(
                    name: shipName, imo: string("P458"), mmsi: string("P587"),
                    tonnage: quantity("P1093"), length: quantity("P2043"),
                    beam: quantity("P2261"), year: year("P729"),
                    operatorName: "", flag: "",
                    imageFile: string("P18")),
                label: localised,
                operatorID: reference("P137"),
                flagID: reference("P17"))
        }
        return result
    }

    private func get(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.agent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
