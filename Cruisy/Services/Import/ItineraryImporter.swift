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
        sourceText = text
        await interpret(text)
    }

    func importPDF(at url: URL) async {
        phase = .reading
        do {
            let text = try await TextRecognizer.text(inPDF: url)
            guard !text.isEmpty else {
                phase = .failed(String(localized: "Non sono riuscito a leggere testo da questo PDF."))
                return
            }
            sourceText = text
            await interpret(text)
        } catch {
            phase = .failed(String(localized: "Non sono riuscito ad aprire il PDF."))
        }
    }

    func importImageFile(at url: URL) async {
        phase = .reading
        do {
            let text = try await TextRecognizer.text(inImageFile: url)
            guard !text.isEmpty else {
                phase = .failed(String(localized: "Non ho trovato testo in questa immagine."))
                return
            }
            sourceText = text
            await interpret(text)
        } catch {
            phase = .failed(String(localized: "Non sono riuscito a leggere l'immagine."))
        }
    }

    /// Pagine arrivate dallo scanner della fotocamera.
    func importScans(_ images: [CGImage]) async {
        phase = .reading
        var text = ""
        for image in images {
            if let page = try? await TextRecognizer.text(in: image) { text += page + "\n" }
        }
        guard !text.isEmpty else {
            phase = .failed(String(localized: "Non ho trovato testo nella scansione."))
            return
        }
        sourceText = text
        await interpret(text)
    }

    // MARK: Interpretazione

    private func interpret(_ text: String) async {
        phase = .interpreting
        let draft = ItineraryTextParser().parse(text)

        guard !draft.isEmpty else {
            phase = .failed(String(localized: "In questo testo non ho riconosciuto un itinerario. Controlla che ci siano le date e i nomi dei porti."))
            return
        }
        self.draft = draft
        phase = .ready
    }

}
