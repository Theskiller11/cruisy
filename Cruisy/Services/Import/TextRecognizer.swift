import Foundation
import Vision
import PDFKit
import UIKit

/// Tira fuori il testo da una foto o da un PDF, sul dispositivo.
enum TextRecognizer {

    /// Riconosce il testo in un'immagine.
    ///
    /// `.accurate` e non `.fast`: qui si legge un orario, e uno "07:00" letto come
    /// "01:00" manderebbe qualcuno al molo sei ore dopo. Vale i decimi di secondo in più.
    static func text(in image: CGImage, minimumTextHeight: Float? = nil) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let minimumTextHeight { request.minimumTextHeightFraction = minimumTextHeight }
        // Le lingue in cui sono scritti gli itinerari che ci aspettiamo.
        request.recognitionLanguages = [Locale.Language(identifier: "it-IT"),
                                        Locale.Language(identifier: "en-US")]

        let observations = try await request.perform(on: image)
        return lines(from: observations)
    }

    /// Le due letture di un'immagine: righe ricostruite per altezza e lettura per
    /// documenti di Vision.
    ///
    /// Nessuna delle due vince sempre. Provate sugli screenshot dell'app di Explora il
    /// 23 settembre 2026: la lettura per documenti dà righe più pulite, ma nel terzo
    /// saltava **del tutto** «Sab 21 Nov · In mare»; le righe per altezza lo tenevano,
    /// storpiato. La fiducia che Vision dichiara non aiuta a scegliere — circa 0,5
    /// anche su «Miami» letto giusto — quindi sceglie chi le usa: `ItineraryImporter`
    /// le passa tutte e due al lettore e tiene quella che ne esce meglio.
    ///
    /// Le letture sono tre, e il 23 settembre 2026 è emerso perché: con le impostazioni
    /// di serie l'OCR di iOS **non vede** «Puerto Plata» nel terzo screenshot, perché il
    /// testo è sotto l'altezza minima (1/32 dell'immagine, e uno screenshot è lungo);
    /// abbassandola lo vede, ma perde «Partenza: 17:00» e «In mare». Nessuna impostazione
    /// legge tutto, quindi `ItineraryImporter` le unisce giorno per giorno
    /// (`ItineraryTextParser.combine`).
    static func readings(of image: CGImage) async -> [String] {
        var readings: [String] = []
        if let lines = try? await text(in: image), !lines.isEmpty { readings.append(lines) }
        if let small = try? await text(in: image, minimumTextHeight: 0.005), !small.isEmpty { readings.append(small) }
        if let document = try? await documentText(in: image), !document.isEmpty { readings.append(document) }
        return readings
    }

    /// La lettura per documenti: le tabelle riga per riga, poi il resto nell'ordine di
    /// lettura. Le tabelle sono il motivo per usarla: in un programma di bordo una riga
    /// di tabella è una tappa, e ricostruirla dall'altezza delle parole sbaglia.
    static func documentText(in image: CGImage) async throws -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "it-IT"),
                                                               Locale.Language(identifier: "en-US")]
        request.textRecognitionOptions.useLanguageCorrection = true
        var result: [String] = []
        for observation in try await request.perform(on: image) {
            let document = observation.document
            let tableBoxes = document.tables.map(\.boundingRegion.boundingBox.cgRect)
            for table in document.tables {
                for row in table.rows {
                    result.append(row.map { $0.content.text.transcript
                        .replacingOccurrences(of: "\n", with: " ") }.joined(separator: "  "))
                }
            }
            for paragraph in document.paragraphs {
                let box = paragraph.boundingRegion.boundingBox.cgRect
                guard !tableBoxes.contains(where: { $0.intersects(box) }) else { continue }
                result.append(paragraph.transcript)
            }
        }
        return result.joined(separator: "\n")
    }

    /// Rimette le parole in righe.
    ///
    /// Vision restituisce blocchi sparsi, e un itinerario è una tabella: se si
    /// concatenasse tutto in fila, la data di una riga finirebbe accanto al porto di
    /// quella dopo. Si raggruppa per altezza sulla pagina, che è il modo più semplice
    /// per ricostruire le righe senza fare analisi di layout.
    private static func lines(from observations: [RecognizedTextObservation]) -> String {
        struct Fragment { let y: CGFloat; let x: CGFloat; let text: String }

        let fragments: [Fragment] = observations.compactMap { observation -> Fragment? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox.cgRect
            return Fragment(y: box.midY, x: box.midX, text: candidate.string)
        }
        guard !fragments.isEmpty else { return "" }

        // Tolleranza verticale: due frammenti entro l'1,2% dell'altezza della pagina
        // stanno sulla stessa riga.
        let tolerance: CGFloat = 0.012
        var rows: [[Fragment]] = []
        for fragment in fragments.sorted(by: { $0.y > $1.y }) {
            if var last = rows.last, let reference = last.first,
               abs(reference.y - fragment.y) <= tolerance {
                last.append(fragment)
                rows[rows.count - 1] = last
            } else {
                rows.append([fragment])
            }
        }
        return rows
            .map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: "  ") }
            .joined(separator: "\n")
    }

    /// Testo da un PDF: il livello di testo, che è esatto; solo se il PDF è una
    /// scansione senza testo, le due letture dell'OCR, che sono approssimative.
    static func readings(inPDF url: URL) async throws -> [String] {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { return [] }

        var embedded = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string { embedded += text + "\n" }
        }
        if embedded.filter({ $0.isLetter || $0.isNumber }).count > 80 { return [embedded] }

        // Scansione senza testo: ogni pagina letta in due modi, e le letture dello
        // stesso tipo si uniscono pagina dopo pagina.
        var byKind: [String] = []
        for index in 0..<min(document.pageCount, 12) {
            guard let page = document.page(at: index), let image = render(page) else { continue }
            for (kind, reading) in await readings(of: image).enumerated() {
                if byKind.count <= kind { byKind.append("") }
                byKind[kind] += reading + "\n"
            }
        }
        return byKind
    }

    /// Una pagina al doppio della misura naturale: l'OCR sui caratteri piccoli di una
    /// tabella a scala 1 sbaglia le cifre.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }

    /// Testo da un file immagine scelto dall'utente.
    static func text(inImageFile url: URL) async throws -> String {
        guard let image = image(inFile: url) else { return "" }
        return try await text(in: image)
    }

    static func image(inFile url: URL) -> CGImage? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)?.cgImage
    }
}
