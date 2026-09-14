import Foundation
import Observation
import UIKit

/// Scarica la foto di un porto.
///
/// **Perché non funziona come per le navi.** Una nave ha un'immagine dichiarata su
/// Wikidata, quindi il nome del file è un dato. Un porto no: si ha solo un nome e
/// delle coordinate. Le due strade possibili sono la ricerca geografica su Commons —
/// che restituisce qualunque cosa sia stata fotografata lì attorno, un gabbiano
/// compreso — e **l'immagine di apertura della voce di Wikipedia**, che qualcuno ha
/// scelto apposta perché rappresenti il posto. Si prende la seconda.
///
/// **E si verificano le coordinate.** «San Juan» è a Porto Rico, in Argentina e nelle
/// Filippine; «Grand Turk» ha una voce sull'isola e una sull'aeroporto. Una foto
/// sbagliata accanto a uno scalo non è un dettaglio estetico: fa dubitare di tutto il
/// resto dell'app. Se la voce trovata sta a più di cinquanta chilometri dal porto
/// salvato, la foto si scarta e non si mostra niente.
///
/// **Legata al thread principale**, e non per abitudine. Il 14 settembre 2026 la
/// schermata dei porti faceva crashare l'app: ogni riga lanciava il proprio `load`, i
/// `load` giravano in parallelo fuori dal thread principale, e tutti modificavano lo
/// stesso insieme `attempted` nello stesso momento. L'insieme si corrompeva e l'app
/// moriva dentro `Set.contains`. Il progetto compila in modalità Swift 5 senza controlli
/// di concorrenza, quindi il compilatore non l'aveva segnalato. Con `@MainActor` lo
/// stato si tocca da un solo posto alla volta; le attese di rete restano fuori dal
/// thread principale, perché le funzioni di `Commons` non sono legate a nessun attore.
@MainActor
@Observable
final class PortPhotoService {

    private(set) var photos: [String: CommonsPhoto] = [:]
    /// I porti per cui si è già provato, riusciti o no: un porto senza foto non si
    /// deve richiedere a ogni ridisegno della lista.
    private var attempted: Set<String> = []

    private let cache = Commons.cacheDirectory("Porti")

    /// Oltre questa distanza fra la voce e il porto, non è lo stesso posto.
    private static let toleranceNauticalMiles: Double = 27   // ~50 km

    /// Le lingue in cui cercare, in ordine. L'italiano per primo perché è la lingua
    /// dell'app; l'inglese come rete di sicurezza, che ha voci per porti che
    /// l'italiano non copre.
    private static let languages = ["it", "en"]

    func photo(for call: PortCall) -> CommonsPhoto? { photos[key(call)] }

    private func key(_ call: PortCall) -> String {
        "\(call.name)|\(String(format: "%.2f,%.2f", call.coordinate.latitude, call.coordinate.longitude))"
    }

    /// - Parameter allowsDownload: falso su rete a consumo senza permesso: si mostra
    ///   solo la cache, e il porto non viene segnato come provato, così la foto arriva
    ///   quando la rete torna a essere gratuita.
    func load(_ call: PortCall, allowsDownload: Bool = true) async {
        let key = key(call)
        guard !attempted.contains(key) else { return }

        if let cached = Commons.readCache(cache, key: key) {
            attempted.insert(key)
            photos[key] = cached
            return
        }
        guard allowsDownload else { return }
        attempted.insert(key)

        for language in Self.languages {
            guard let found = await lead(for: call, language: language) else { continue }
            guard let image = await Commons.downloadImage(at: found.url) else { continue }
            let file = Commons.fileName(fromUploadURL: found.url) ?? ""
            let (author, licence) = await Commons.credit(for: file)
            // Senza credito non si mostra: è la condizione della licenza.
            guard !author.isEmpty || !licence.isEmpty else { continue }

            let photo = CommonsPhoto(image: image, author: author, licence: licence)
            photos[key] = photo
            Commons.writeCache(photo, to: cache, key: key)
            return
        }
    }

    /// L'immagine di apertura della voce, se la voce è davvero di quel posto.
    private func lead(for call: PortCall, language: String) async -> (url: URL, title: String)? {
        guard let name = Commons.escape(call.name),
              let url = URL(string: "https://\(language).wikipedia.org/w/api.php?action=query&titles=\(name)&prop=pageimages%7Ccoordinates&piprop=original&redirects=1&format=json"),
              let root = await Commons.json(url),
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any],
              let page = pages.values.first as? [String: Any],
              let original = page["original"] as? [String: Any],
              let source = original["source"] as? String,
              let image = URL(string: source),
              PhotoDownloadPolicy.isPhotograph(image)
        else { return nil }

        // La verifica che rende la cosa affidabile invece che carina.
        guard let coordinates = page["coordinates"] as? [[String: Any]],
              let first = coordinates.first,
              let lat = first["lat"] as? Double, let lon = first["lon"] as? Double
        else { return nil }
        let distance = Geo.nauticalMiles(from: call.coordinate,
                                         to: Coordinate(latitude: lat, longitude: lon))
        guard distance <= Self.toleranceNauticalMiles else { return nil }

        return (image, page["title"] as? String ?? call.name)
    }
}
