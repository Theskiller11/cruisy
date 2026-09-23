import SwiftUI
import PhotosUI
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
    @Environment(\.livery) private var livery
    @State private var importer = ItineraryImporter()
    @State private var pasted = ""
    @State private var isScanning = false
    @State private var isPickingFile = false
    @State private var photoItems: [PhotosPickerItem] = []
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
                // Inserire dati è lavoro da modulo di sistema, non da documento di
                // bordo: il biglietto sta nelle schermate della crociera, qui comanda
                // iOS, che di caselle di testo e tastiere sa più di noi.
                Form {
                    Section {
                        editor
                    } header: {
                        Text("Incolla la conferma della crociera")
                    } footer: {
                        Text("L'email della compagnia, la pagina del sito, una foto del programma di bordo. Basta che ci siano le date e i nomi dei porti: al resto pensa Cruisy, e tutto resta sul telefono.")
                    }

                    Section {
                        // Prima le foto: gli screenshot dell'app della compagnia sono il
                        // modo più comune di avere l'itinerario sul telefono, e stanno in
                        // Foto, non in File. Il selettore gira fuori dall'app: Cruisy vede
                        // solo le immagini scelte, e non chiede il permesso alla libreria.
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 12,
                                     selectionBehavior: .ordered, matching: .images) {
                            Label("Dalle foto", systemImage: "photo.on.rectangle")
                        }
                        Button { isScanning = true } label: {
                            Label("Scansiona", systemImage: "doc.viewfinder")
                        }
                        Button { isPickingFile = true } label: {
                            Label("Importa file", systemImage: "folder")
                        }
                    } footer: {
                        Text("Puoi scegliere più screenshot insieme, nell'ordine dei giorni: le parti ripetute da uno all'altro si uniscono da sole.")
                    }
                    .disabled(importer.isBusy)

                    if case .failed(let message) = importer.phase {
                        Section {
                            Label(LocalizedStringKey(message), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .tint(livery.tint)
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
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var images: [CGImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data)?.cgImage {
                            images.append(image)
                        }
                    }
                    photoItems = []
                    await importer.importPhotos(images)
                }
            }
            .fileImporter(isPresented: $isPickingFile,
                          allowedContentTypes: [.pdf, .image, .plainText],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task {
                    if urls.count > 1 {
                        // Più file insieme: screenshot salvati in File.
                        await importer.importImageFiles(at: urls)
                    } else if url.pathExtension.lowercased() == "pdf" {
                        await importer.importPDF(at: url)
                    } else if let text = try? String(contentsOf: url, encoding: .utf8),
                              !text.isEmpty {
                        await importer.importText(text)
                    } else {
                        await importer.importImageFiles(at: [url])
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

    /// La casella dove si incolla. Il segnaposto è un esempio vero di due righe:
    /// dice che formato accettiamo meglio di qualunque spiegazione.
    private var editor: some View {
        TextEditor(text: $pasted)
            .focused($isEditorFocused)
            .font(.callout)
            .frame(minHeight: 210)
            .overlay(alignment: .topLeading) {
                if pasted.isEmpty {
                    Text("Sab 15 nov · San Juan · 14:00 → 20:00\nDom 16 nov · Charlotte Amalie · 07:00 → 16:00\n…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(importer.phase == .reading
                     ? "Leggo il documento…"
                     : "Metto in ordine l'itinerario…")
                    .font(TicketType.rowDetail)
                    .foregroundStyle(.secondary)
            }
            .padding(26)
            .background(.regularMaterial, in: .rect(cornerRadius: 24))
        }
        .transition(.opacity)
    }
}
