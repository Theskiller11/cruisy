import Testing
import Foundation

/// Il catalogo delle stringhe, letto dal sorgente.
///
/// `xcodebuild` non aggiunge le chiavi nuove al catalogo, e per settimane l'inglese è
/// rimasto indietro senza che nessuno se ne accorgesse: il 14 settembre 2026 mancavano
/// 42 traduzioni. Adesso le chiavi si sincronizzano con `scripts/sync-strings.sh`, e
/// questo test fallisce se una resta senza inglese o se una traduzione perde un
/// segnaposto — che in inglese farebbe comparire «%@» sullo schermo, o peggio il
/// numero sbagliato al posto giusto.
///
/// Limite: vede solo le chiavi già nel catalogo. Una frase nuova entra nel catalogo
/// solo dopo `scripts/sync-strings.sh`; prima di quello il test non può saperne niente.
@Suite("Catalogo delle stringhe")
struct LocalizationTests {

    private struct Entry {
        let key: String
        let english: String?
        let isStale: Bool
        let shouldTranslate: Bool
    }

    private func entries() throws -> [Entry] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CruisyShared/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        return strings.map { key, value in
            let localizations = value["localizations"] as? [String: Any]
            let en = localizations?["en"] as? [String: Any]
            let unit = en?["stringUnit"] as? [String: Any]
            return Entry(key: key,
                         english: unit?["value"] as? String,
                         isStale: (value["extractionState"] as? String) == "stale",
                         shouldTranslate: (value["shouldTranslate"] as? Bool) ?? true)
        }
    }

    /// I segnaposto di una stringa, senza la posizione: `%1$@` e `%@` sono lo stesso.
    private func placeholders(_ text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(lld|ld|d|@|f|\.\d+f)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }.sorted()
    }

    @Test("Ogni chiave traducibile ha l'inglese")
    func everyKeyHasEnglish() throws {
        let missing = try entries().filter { $0.shouldTranslate && !$0.isStale && ($0.english ?? "").isEmpty }
        #expect(missing.isEmpty, "senza inglese: \(missing.map(\.key).prefix(10))")
    }

    @Test("Nessuna chiave stantia")
    func noStaleKeys() throws {
        let stale = try entries().filter(\.isStale)
        #expect(stale.isEmpty, "stantie: \(stale.map(\.key).prefix(10))")
    }

    @Test("Le traduzioni portano gli stessi segnaposto dell'originale")
    func placeholdersSurviveTranslation() throws {
        for entry in try entries() {
            guard let english = entry.english, entry.shouldTranslate else { continue }
            #expect(placeholders(entry.key) == placeholders(english),
                    "«\(entry.key.prefix(50))» → «\(english.prefix(50))»")
        }
    }
}
