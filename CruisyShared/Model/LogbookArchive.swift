import Foundation

/// Dove vive il diario su disco.
///
/// Accanto alla crociera, nello stesso contenitore condiviso e con le stesse
/// regole: **incluso nei backup**. Le miglia di una vita di crociere non si
/// riscaricano da nessuna parte.
public enum LogbookArchive {

    private static var fileURL: URL? {
        let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: VoyageArchive.appGroup)
        let base = shared ?? (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil, create: true))
        guard let base else { return nil }
        let folder = base.appendingPathComponent("Cruisy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("logbook.json")
    }

    public static func load() -> Logbook {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return Logbook() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Logbook.self, from: data)) ?? Logbook()
    }

    public static func save(_ logbook: Logbook) throws {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(logbook).write(to: url, options: .atomic)
    }
}
