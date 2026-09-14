import Foundation

/// Le navi imparate dopo la compilazione dell'app.
///
/// `ships.bin` è una fotografia di Wikidata al giorno in cui è stata costruita: una
/// nave varata dopo, o aggiunta a Wikidata dopo, non ci sarebbe. Questo file la
/// affianca — piccolo, sul dispositivo, **incluso nei backup** come la crociera.
///
/// Sta nello stesso contenitore condiviso della crociera perché anche i widget
/// mostrano il nome della nave, e devono vedere quello aggiornato.
enum ShipOverlay {

    private static var fileURL: URL? {
        let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: VoyageArchive.appGroup)
        let base = shared ?? (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil, create: true))
        guard let base else { return nil }
        let folder = base.appendingPathComponent("Cruisy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("ships-extra.json")
    }

    /// La forma su disco. Deliberatamente separata da `ShipRecord`: il record è un
    /// tipo dell'interfaccia e cambierà; il file no, o smetterebbe di rileggersi.
    private struct Stored: Codable {
        var name: String
        var imo: String
        var mmsi: String
        var tonnage: Double
        var length: Double
        var beam: Double
        var year: Int
        var operatorName: String
        var flag: String
        var imageFile: String

        init(_ r: ShipRecord) {
            name = r.name; imo = r.imo; mmsi = r.mmsi
            tonnage = r.tonnage; length = r.length; beam = r.beam
            year = r.year; operatorName = r.operatorName; flag = r.flag
            imageFile = r.imageFile
        }

        var record: ShipRecord {
            ShipRecord(name: name, imo: imo, mmsi: mmsi, tonnage: tonnage, length: length,
                       beam: beam, year: year, operatorName: operatorName, flag: flag,
                       imageFile: imageFile)
        }
    }

    static func load() -> [String: ShipRecord] {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: Stored].self, from: data)
        else { return [:] }
        return stored.mapValues(\.record)
    }

    static func save(_ records: [String: ShipRecord]) {
        guard let url = fileURL else { return }
        let stored = records.mapValues(Stored.init)
        try? JSONEncoder().encode(stored).write(to: url, options: .atomic)
    }

    /// Quante navi sono state imparate. Serve alle Impostazioni, per poterle
    /// dimenticare tutte insieme.
    static var count: Int { load().count }

    static func forgetAll() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
