import SwiftUI
import UniformTypeIdentifiers

/// Da qui l'itinerario entra nell'app.
///
/// Non c'è un archivio delle partenze dentro Cruisy, e non può esserci: gli orari di
/// una compagnia sono roba sua, e scaricarli da qualche parte farebbe cadere la
/// promessa che l'app funziona senza rete. Quindi l'itinerario lo porti tu — incollato,
/// fotografato o importato — e l'app fa il lavoro noioso di metterlo in ordine.
struct ItineraryImportView: View {
    let onConfirm: (Voyage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var importer = ItineraryImporter()
    @State private var pasted = ""
    @State private var isScanning = false
    @State private var isPickingFile = false
    @FocusState private var isEditorFocused: Bool

    #if DEBUG
    /// `-importDemo` riempie la casella con un itinerario di esempio, per poter
    /// provare la lettura senza incollare a mano a ogni avvio.
    private static let demoText = """
        La tua crociera è confermata
        Nave: Explora III
        Prenotazione 4471829

        Giorno 1 — Sabato 15 novembre
        San Juan, Porto Rico
        Imbarco dalle 14:00. La nave parte alle 20:00.
        Tutti a bordo entro le 19:00.

        Giorno 2 — Domenica 16 novembre
        Charlotte Amalie, St. Thomas
        Arrivo 07:00 · Partenza 16:00

        Giorno 3 — Lunedì 17 novembre
        Gustavia — sbarco con tender
        Arrivo 08:00 · Partenza 18:00

        Giorno 4 — Martedì 18 novembre
        Giorno di mare

        Giorno 5 — Mercoledì 19 novembre
        Puerto Plata, Repubblica Dominicana
        Arrivo 09:00 · Partenza 18:00 · All aboard 17:30

        Giorno 6 — Giovedì 20 novembre
        Grand Turk
        Arrivo 08:00 · Partenza 17:00

        Giorno 7 — Venerdì 21 novembre
        Navigazione

        Giorno 8 — Sabato 22 novembre
        Miami, Florida
        Arrivo 07:00 · sbarco
        """
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.seaBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        editor
                        sources
                        if case .failed(let message) = importer.phase {
                            StaleDataNotice(message: LocalizedStringKey(message))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                #if DEBUG
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("-importDemo"),
                          pasted.isEmpty else { return }
                    pasted = Self.demoText
                    // Con `-importLeggi` va avanti da solo fino al riesame.
                    if ProcessInfo.processInfo.arguments.contains("-importLeggi") {
                        await importer.importText(Self.demoText)
                    }
                }
                #endif

                if importer.isBusy { busyOverlay }
            }
            .navigationTitle("Importa itinerario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Leggi") {
                        isEditorFocused = false
                        Task { await importer.importText(pasted) }
                    }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).count < 20
                              || importer.isBusy)
                }
            }
            .sheet(isPresented: $isScanning) {
                DocumentScanner { pages in
                    guard !pages.isEmpty else { return }
                    Task { await importer.importScans(pages) }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $isPickingFile,
                          allowedContentTypes: [.pdf, .image, .plainText]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    if url.pathExtension.lowercased() == "pdf" {
                        await importer.importPDF(at: url)
                    } else if let text = try? String(contentsOf: url, encoding: .utf8),
                              !text.isEmpty {
                        await importer.importText(text)
                    } else {
                        await importer.importImageFile(at: url)
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { importer.phase == .ready && importer.draft != nil },
                set: { if !$0 { importer.reset() } })) {
                if let draft = importer.draft {
                    ImportReviewView(draft: draft, sourceText: importer.sourceText) { voyage in
                        onConfirm(voyage)
                        dismiss()
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Incolla la conferma della crociera")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.inkPrimary)
            Text("L'email della compagnia, la pagina del sito, una foto del programma di bordo. Basta che ci siano le date e i nomi dei porti: al resto pensa Cruisy, e tutto resta sul telefono.")
                .font(Type.rowDetail)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var editor: some View {
        TextEditor(text: $pasted)
            .focused($isEditorFocused)
            .font(.callout)
            .foregroundStyle(Palette.inkPrimary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 210)
            .padding(12)
            .glassSurface(cornerRadius: 20, prominence: .chip)
            .overlay(alignment: .topLeading) {
                if pasted.isEmpty {
                    Text("Sab 15 nov · San Juan · 14:00 → 20:00\nDom 16 nov · Charlotte Amalie · 07:00 → 16:00\n…")
                        .font(.callout)
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
    }

    private var sources: some View {
        HStack(spacing: 10) {
            Button { isScanning = true } label: {
                Label("Scansiona", systemImage: "doc.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.glass)

            Button { isPickingFile = true } label: {
                Label("Importa file", systemImage: "folder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.glass)
        }
        .tint(Palette.action)
        .disabled(importer.isBusy)
    }

    private var busyOverlay: some View {
        ZStack {
            Palette.abyss.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(importer.phase == .reading
                     ? "Leggo il documento…"
                     : "Metto in ordine l'itinerario…")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(26)
            .glassSurface(cornerRadius: 24, prominence: .chrome)
        }
        .transition(.opacity)
    }
}
