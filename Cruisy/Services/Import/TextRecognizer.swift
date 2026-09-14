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
    static func text(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Le lingue in cui sono scritti gli itinerari che ci aspettiamo.
        request.recognitionLanguages = [Locale.Language(identifier: "it-IT"),
                                        Locale.Language(identifier: "en-US")]

        let observations = try await request.perform(on: image)
        return lines(from: observations)
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

    /// Testo da un PDF.
    ///
    /// Prima si prova il livello di testo, che è esatto; solo se il PDF è una
    /// scansione senza testo si passa all'OCR, che è approssimativo.
    static func text(inPDF url: URL) async throws -> String {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else { return "" }

        var embedded = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string {
                embedded += text + "\n"
            }
        }
        let meaningful = embedded.filter { $0.isLetter || $0.isNumber }.count
        if meaningful > 80 { return embedded }

        // Nessun livello di testo utile: si rendono le pagine e si legge con l'OCR.
        var recognised = ""
        for index in 0..<min(document.pageCount, 12) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            // Il doppio della misura naturale: l'OCR sui caratteri piccoli di una
            // tabella a scala 1 sbaglia le cifre.
            let scale: CGFloat = 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
            if let cgImage = image.cgImage {
                recognised += (try await text(in: cgImage)) + "\n"
            }
        }
        return recognised
    }

    /// Testo da un file immagine scelto dall'utente.
    static func text(inImageFile url: URL) async throws -> String {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)?.cgImage else { return "" }
        return try await text(in: image)
    }
}
