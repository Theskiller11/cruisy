import Foundation
import Observation
import CoreGraphics

/// Prende un testo o un documento e ne ricava un itinerario da rivedere.
///
/// Un lettore solo, deterministico: a parità di ingresso dà sempre lo stesso
/// risultato, quindi si può collaudare, e funziona su qualunque iPhone senza
/// dipendere da modelli che possono non esserci. Una strada sviluppata bene batte
/// due sviluppate a metà.
@MainActor
@Observable
final class ItineraryImporter {

    enum Phase: Equatable {
        case idle
        /// Sta estraendo il testo da un documento.
        case reading
        /// Sta interpretando il testo.
        case interpreting
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var draft: ItineraryDraft?
    /// Il testo da cui è nato il bozzetto, mostrato nel riesame per il confronto.
    private(set) var sourceText: String = ""

    var isBusy: Bool { phase == .reading || phase == .interpreting }

    func reset() {
        phase = .idle
        draft = nil
        sourceText = ""
    }

    // MARK: Ingressi

    func importText(_ text: String) async {
        await interpret(text, source: .pastedText)
    }

    func importPDF(at url: URL) async {
        phase = .reading
        do {
            let readings = try await TextRecognizer.readings(inPDF: url)
            guard !readings.isEmpty else {
                phase = .failed(String(localized: "Non sono riuscito a leggere testo da questo PDF."))
                return
            }
            await interpretBest(readings, source: .pdf)
        } catch {
            phase = .failed(String(localized: "Non sono riuscito ad aprire il PDF."))
        }
    }

    /// Una o più immagini scelte dai File, lette nell'ordine in cui sono state scelte.
    func importImageFiles(at urls: [URL]) async {
        await importImages(urls.compactMap(TextRecognizer.image(inFile:)), source: .images)
    }

    /// Pagine arrivate dallo scanner della fotocamera.
    func importScans(_ images: [CGImage]) async {
        await importImages(images, source: .scannedDocument)
    }

    /// Foto e screenshot scelti dall'app Foto.
    ///
    /// È il modo in cui la gente ha l'itinerario in mano: tre screenshot dell'app della
    /// compagnia, uno dopo l'altro e sovrapposti. Si leggono nell'ordine della scelta e
    /// si uniscono in un testo solo; le tappe ripetute da una foto all'altra le fonde il
    /// lettore.
    func importPhotos(_ images: [CGImage]) async {
        await importImages(images, source: .images)
    }

    /// Ogni immagine si legge in due modi (`TextRecognizer.readings`); le letture dello
    /// stesso tipo si uniscono immagine dopo immagine, e al lettore arrivano entrambe.
    private func importImages(_ images: [CGImage], source: ItineraryDraft.Source) async {
        phase = .reading
        var byKind: [String] = []
        for image in images {
            for (kind, reading) in await TextRecognizer.readings(of: image).enumerated() {
                if byKind.count <= kind { byKind.append("") }
                byKind[kind] += reading + "\n"
            }
        }
        guard byKind.contains(where: { !$0.isEmpty }) else {
            phase = .failed(String(localized: "Non ho trovato testo in queste immagini."))
            return
        }
        await interpretBest(byKind, source: source)
    }

    // MARK: Interpretazione

    private func interpret(_ text: String, source: ItineraryDraft.Source) async {
        await interpretBest([text], source: source)
    }

    /// Legge ogni testo e tiene l'itinerario che ne esce meglio (`ItineraryDraft.quality`).
    private func interpretBest(_ texts: [String], source: ItineraryDraft.Source) async {
        phase = .interpreting
        let parser = ItineraryTextParser()
        var candidates = texts.map { (text: $0, draft: parser.parse($0)) }
        // Più letture: anche la loro unione è un candidato, e a parità vince lei, che
        // ha visto tutto quello che hanno visto le altre.
        if candidates.count > 1 {
            let union = (text: texts.joined(separator: "\n———\n"),
                         draft: parser.combine(candidates.map(\.draft)))
            candidates.insert(union, at: 0)
        }
        guard let best = candidates.reduce(nil as (text: String, draft: ItineraryDraft)?, { best, next in
            guard let best else { return next }
            return next.draft.quality > best.draft.quality ? next : best
        }) else {
            phase = .failed(String(localized: "In questo testo non ho riconosciuto un itinerario. Controlla che ci siano le date e i nomi dei porti."))
            return
        }
        sourceText = best.text
        var draft = best.draft
        draft.source = source

        guard !draft.isEmpty else {
            phase = .failed(String(localized: "In questo testo non ho riconosciuto un itinerario. Controlla che ci siano le date e i nomi dei porti."))
            return
        }
        self.draft = draft
        phase = .ready
    }

}
