import Foundation
import UIKit

/// Una fotografia presa da Wikimedia Commons, con il credito che la accompagna.
///
/// I campi viaggiano **insieme** di proposito: la foto senza il credito non si può
/// mostrare, quindi non esiste uno stato in cui l'app ha l'una senza l'altro.
struct CommonsPhoto: Equatable, Sendable {
    var image: UIImage
    /// Chi l'ha scattata.
    var author: String
    /// Con quale licenza la mette a disposizione.
    var licence: String

    var credit: String {
        [author, licence].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Il nome che aveva prima che le foto fossero anche dei porti.
typealias ShipPhoto = CommonsPhoto

/// Quando si possono scaricare le foto, e quali.
///
/// **Le reti a consumo.** Sulle navi e in roaming internet si paga a peso: una foto da
/// 900 pixel costa quanto decine di previsioni meteo. Fino al 14 settembre 2026 le foto
/// si scaricavano su qualunque rete — `Reachability` sapeva riconoscere una rete
/// costosa, ma nessuno glielo chiedeva. Adesso su rete a consumo si scaricano solo se
/// chi usa l'app lo ha permesso; quelle già in cache si mostrano sempre.
///
/// Limite onesto: il Wi-Fi di bordo per iOS è un Wi-Fi qualunque, non una rete
/// costosa, a meno che non ci si attivi sopra Risparmio dati. Questa regola protegge il
/// roaming e l'hotspot, non il pacchetto internet della nave.
enum PhotoDownloadPolicy {

    static let meteredKey = "cruisy.photosOnMeteredNetworks"

    /// Chi usa l'app ha detto che le foto si possono scaricare anche su rete a consumo.
    static var allowsMetered: Bool { UserDefaults.standard.bool(forKey: meteredKey) }

    static func allows(isMetered: Bool, allowsMetered: Bool = PhotoDownloadPolicy.allowsMetered) -> Bool {
        !isMetered || allowsMetered
    }

    /// Se l'immagine di apertura di una voce può essere la foto di un porto.
    ///
    /// Solo JPEG. Stemmi, bandiere, cartine di posizione e loghi — che su Wikipedia
    /// aprono spesso la voce di una città — sono quasi sempre SVG o PNG; le fotografie
    /// quasi sempre JPEG. Una regola grossolana, ma che scarta proprio gli errori che
    /// si vedono di più.
    static func isPhotograph(_ url: URL) -> Bool {
        ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }
}

/// Le parti in comune fra la foto della nave e quella del porto.
///
/// **Perché le foto non sono impacchettate nell'app**: le fotografie non sono fatti.
/// Su Commons sono tutte libere — è condizione per caricarcele — ma quasi tutte sotto
/// licenze che obbligano a **citare l'autore**. Impacchettarne mille alla cieca
/// vorrebbe dire mille crediti da mantenere, e un'app più pesante per qualcosa che si
/// guarda una volta. Si scarica quella che serve, si mostra col credito, si tiene in
/// cache.
enum Commons {

    private static let agent = "Cruisy/1.0 (app iOS personale)"

    /// I titoli di Commons possono contenere `&`, `+`, `?`: dentro un URL vanno
    /// codificati tutti, o la query si spezza e il percorso porta altrove. Il `%`
    /// si codifica per primo, se no un titolo già codificato diventerebbe `%2520`.
    static func escape(_ file: String) -> String? {
        let plain = file.removingPercentEncoding ?? file
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~ ,'()!*:@"))
        return plain.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "%20")
    }

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func json(_ url: URL) async -> [String: Any]? {
        guard let (data, _) = try? await URLSession.shared.data(for: request(url)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func downloadImage(file: String, width: Int = 900) async -> UIImage? {
        guard let encoded = escape(file),
              let url = URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=\(width)")
        else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(for: request(url)) else { return nil }
        return UIImage(data: data)
    }

    static func downloadImage(at url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(for: request(url)) else { return nil }
        return UIImage(data: data)
    }

    /// Autore e licenza di un file, dai metadati di Commons.
    static func credit(for file: String) async -> (author: String, licence: String) {
        guard let encoded = escape("File:\(file)"),
              let url = URL(string: "https://commons.wikimedia.org/w/api.php?action=query&titles=\(encoded)&prop=imageinfo&iiprop=extmetadata&format=json"),
              let root = await json(url),
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any],
              let page = pages.values.first as? [String: Any],
              let infos = page["imageinfo"] as? [[String: Any]],
              let meta = infos.first?["extmetadata"] as? [String: Any]
        else { return ("", "") }

        func field(_ key: String) -> String {
            guard let entry = meta[key] as? [String: Any],
                  let value = entry["value"] as? String else { return "" }
            // I campi di Commons arrivano in HTML: qui serve solo il testo.
            return value.replacingOccurrences(of: "<[^>]+>", with: "",
                                              options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (cleanAuthor(field("Artist")), field("LicenseShortName"))
    }

    /// L'autore da scrivere nel credito, ricavato dal campo `Artist` di Commons.
    ///
    /// Quel campo non è sempre un nome. Per le foto caricate anni fa è spesso una
    /// frase — «Originally uploaded at en.wikipedia by en:User:Evaneggers as …»,
    /// «This image or media was taken or created by Matt H. Wade. To see …» — e nella
    /// pastiglia del credito finiva tagliata a metà. Si cerca il nome dopo l'ultimo
    /// «by», si toglie il prefisso da nome utente, e se resta qualcosa di troppo lungo
    /// per essere un nome si ripiega su «Wikimedia Commons»: la licenza resta accanto,
    /// e il riferimento al file originale è comunque dove l'autore l'ha pubblicato.
    static func cleanAuthor(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }

        if name.count > 40, let by = name.range(of: " by ", options: [.backwards, .caseInsensitive]) {
            name = String(name[by.upperBound...])
            // Il nome finisce al primo « as », «(», «,» o al primo punto che chiude una
            // parola vera: il punto dopo un'iniziale («Matt H. Wade») non conta.
            for marker in [" as ", " (", ", "] {
                if let cut = name.range(of: marker) { name = String(name[..<cut.lowerBound]) }
            }
            var end = name.endIndex
            var index = name.startIndex
            while let dot = name[index...].firstIndex(of: ".") {
                let word = name[..<dot].split(separator: " ").last ?? ""
                if word.count > 1 { end = dot; break }
                index = name.index(after: dot)
            }
            name = String(name[..<end])
        }

        // «en:User:Evaneggers», «User:Evaneggers» → «Evaneggers».
        if let colon = name.range(of: "User:", options: .caseInsensitive) {
            name = String(name[colon.upperBound...])
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        return name.isEmpty || name.count > 40 ? "Wikimedia Commons" : name
    }

    /// Il nome del file dentro un URL di upload.wikimedia.org.
    ///
    /// Serve perché l'immagine di apertura di una voce arriva come URL, mentre il
    /// credito si chiede per nome di file. Senza questo passaggio la foto ci sarebbe
    /// ma non si potrebbe mostrare, perché mancherebbe l'autore.
    static func fileName(fromUploadURL url: URL) -> String? {
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        // I ritagli si chiamano "800px-Nome.jpg": il file vero è quello senza prefisso.
        if let range = name.range(of: #"^\d+px-"#, options: .regularExpression) {
            return String(name[range.upperBound...])
        }
        return name.isEmpty ? nil : name
    }

    // MARK: Cache

    /// La chiave del file su disco. **Non** `hashValue`: quello cambia seme a ogni
    /// processo, e una cache che non si ritrova al riavvio non è una cache. FNV-1a
    /// dà lo stesso nome ogni volta.
    static func stem(for key: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static func cacheDirectory(_ name: String) -> URL? {
        let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
        let folder = base?.appendingPathComponent(name, isDirectory: true)
        if let folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static func readCache(_ folder: URL?, key: String) -> CommonsPhoto? {
        guard let folder else { return nil }
        let stem = stem(for: key)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(stem + ".jpg")),
              let image = UIImage(data: data),
              let credit = try? String(contentsOf: folder.appendingPathComponent(stem + ".txt"),
                                       encoding: .utf8)
        else { return nil }
        let parts = credit.components(separatedBy: "\n")
        // Pulito anche in lettura: le foto scaricate prima di `cleanAuthor` hanno in
        // cache la frase intera, e un nome già pulito non cambia.
        return CommonsPhoto(image: image, author: cleanAuthor(parts.first ?? ""),
                            licence: parts.count > 1 ? parts[1] : "")
    }

    static func writeCache(_ photo: CommonsPhoto, to folder: URL?, key: String) {
        guard let folder, let data = photo.image.jpegData(compressionQuality: 0.8) else { return }
        let stem = stem(for: key)
        try? data.write(to: folder.appendingPathComponent(stem + ".jpg"))
        try? "\(photo.author)\n\(photo.licence)".write(
            to: folder.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
    }
}
