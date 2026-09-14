import Foundation

/// Dove vive la traccia della crociera in corso.
///
/// In un file **suo**, accanto alla crociera e al diario. Non dentro `Voyage`: la
/// traccia cresce di continuo mentre la crociera cambia raramente, e tenerle
/// insieme vorrebbe dire riscrivere l'itinerario ogni due minuti — con il widget
/// che rilegge lo stesso file mentre lo si scrive.
///
/// Incluso nei backup, come il diario: una traversata registrata non si rifà.
public enum TrackArchive {

    private static var fileURL: URL? {
        let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: VoyageArchive.appGroup)
        let base = shared ?? (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil, create: true))
        guard let base else { return nil }
        let folder = base.appendingPathComponent("Cruisy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("track.json")
    }

    public static func load() -> Track {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return Track() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Track.self, from: data)) ?? Track()
    }

    public static func save(_ track: Track) throws {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(track).write(to: url, options: .atomic)
    }

    public static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
