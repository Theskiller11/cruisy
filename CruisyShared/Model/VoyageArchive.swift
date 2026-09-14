import Foundation

/// Dove vive la crociera su disco.
///
/// In un contenitore condiviso fra app ed estensione: il widget e la Live Activity
/// girano in un altro processo e non vedrebbero mai i file dell'app. Se il gruppo
/// non fosse disponibile si ripiega sul contenitore dell'app — l'app continua a
/// funzionare, e a restare senza sono solo i widget.
///
/// Il file **non** è escluso dai backup: l'itinerario l'ha digitato una persona, e
/// perderlo al cambio di telefono sarebbe imperdonabile. Solo le cache, che si
/// riscaricano, andranno escluse.
public enum VoyageArchive {

    public static let appGroup = "group.it.matteopapini.Cruisy"

    private static var directory: URL? {
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        let base = shared ?? (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil, create: true))
        guard let base else { return nil }
        let folder = base.appendingPathComponent("Cruisy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var fileURL: URL? {
        directory?.appendingPathComponent("voyage.json")
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func load() -> Voyage? {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decoder.decode(Voyage.self, from: data)
    }

    #if DEBUG
    private static var backupURL: URL? {
        directory?.appendingPathComponent("voyage-backup.json")
    }

    /// Mette da parte la crociera vera prima di scriverci sopra una di prova.
    ///
    /// Esiste perché il collaudo su telefono deve poter sovrascrivere l'archivio —
    /// è l'unico modo perché il widget veda qualcosa — senza far perdere a nessuno
    /// l'itinerario che ha digitato.
    public static func backUp() throws {
        guard let url = fileURL, let backup = backupURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        if FileManager.default.fileExists(atPath: backup.path) { return }  // già salvata
        try FileManager.default.copyItem(at: url, to: backup)
    }

    /// Rimette la crociera vera e butta la copia.
    @discardableResult
    public static func restore() -> Voyage? {
        guard let url = fileURL, let backup = backupURL,
              FileManager.default.fileExists(atPath: backup.path) else { return nil }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.moveItem(at: backup, to: url)
        return load()
    }

    public static var hasBackup: Bool {
        guard let backup = backupURL else { return false }
        return FileManager.default.fileExists(atPath: backup.path)
    }
    #endif

    public static func save(_ voyage: Voyage?) throws {
        guard let url = fileURL else { return }
        if let voyage {
            try encoder.encode(voyage).write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
