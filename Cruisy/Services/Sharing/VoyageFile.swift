import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Il tipo di documento di Cruisy, dichiarato in `Cruisy-Info.plist`.
    static let cruisyVoyage = UTType(exportedAs: "it.matteopapini.cruisy.voyage")
}

/// La crociera come file, da mandare a chi vuoi.
///
/// È la risposta al "ritrovare la crociera altrove" e al "condividerla con chi viaggia
/// con me" **senza** account e senza capability da chiedere ad Apple. In più, in
/// crociera funziona meglio della sincronizzazione: AirDrop fra due telefoni sullo
/// stesso ponte non ha bisogno di rete, mentre iCloud in mezzo all'oceano non
/// sincronizzerebbe comunque niente.
enum VoyageFile {

    static let fileExtension = "cruisy"

    /// L'involucro salvato su disco: la versione serve a poter cambiare formato
    /// domani senza che un file vecchio faccia cadere l'app.
    private struct Envelope: Codable {
        var format: Int
        var voyage: Voyage
    }

    private static let currentFormat = 1

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func data(for voyage: Voyage) throws -> Data {
        try encoder.encode(Envelope(format: currentFormat, voyage: voyage))
    }

    static func voyage(from data: Data) throws -> Voyage {
        do {
            return try decoder.decode(Envelope.self, from: data).voyage
        } catch {
            // Tollera anche una crociera salvata senza involucro, com'è il file
            // interno dell'app: rende il formato più facile da maneggiare a mano.
            return try decoder.decode(Voyage.self, from: data)
        }
    }

    /// Un nome di file leggibile: "Explora III · 15 nov.cruisy".
    static func fileName(for voyage: Voyage) -> String {
        let ship = voyage.shipName.trimmingCharacters(in: .whitespaces)
        let start = voyage.startsAt.map { Format.dayMonth($0, clock: voyage.clock) }
        let stem = [ship.isEmpty ? "Crociera" : ship, start].compactMap(\.self).joined(separator: " · ")
        // Le barre romperebbero il percorso.
        return stem.replacingOccurrences(of: "/", with: "-") + "." + fileExtension
    }

    /// Scrive il file in una cartella temporanea, pronto per il foglio di condivisione.
    static func export(_ voyage: Voyage) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Condivisione", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(for: voyage))
        try data(for: voyage).write(to: url, options: .atomic)
        return url
    }

    /// Legge una crociera da un file ricevuto.
    static func read(from url: URL) throws -> Voyage {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        return try voyage(from: Data(contentsOf: url))
    }
}
