import SwiftUI

/// Lo stato iniziale: nessuna crociera inserita.
///
/// Niente dati finti a riempire il vuoto. Un'app che si presenta con una crociera
/// inventata addosso è contenuto segnaposto, e non supera la revisione.
struct NoVoyageView: View {
    @Environment(VoyageStore.self) private var store
    @State private var isEditing = false
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "ferry")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.underway)

            VStack(spacing: 8) {
                Text("Nessuna crociera")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.inkPrimary)
                Text("Incolla o fotografa la conferma della compagnia: Cruisy ne ricava l'itinerario e da lì calcola i countdown, anche senza rete a bordo.")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    isImporting = true
                } label: {
                    Label("Importa l'itinerario", systemImage: "text.viewfinder")
                        .font(Type.rowTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.underway)

                Button("Inserisci a mano") { isEditing = true }
                    .font(Type.rowDetail)
                    .tint(Palette.action)
            }
        }
        .padding(.horizontal, 32)
        .sheet(isPresented: $isEditing) {
            VoyageEditor(voyage: nil) { store.replace(with: $0) }
        }
        .sheet(isPresented: $isImporting) {
            ItineraryImportView { store.replace(with: $0) }
        }
        #if DEBUG
        // `-importDemo` apre direttamente l'importazione: serve a pilotare il flusso
        // dal simulatore senza dover toccare lo schermo.
        .task {
            if ProcessInfo.processInfo.arguments.contains("-importDemo") { isImporting = true }
        }
        #endif
    }
}

#Preview {
    ZStack {
        Palette.seaBackground.ignoresSafeArea()
        NoVoyageView().environment(VoyageStore.previewEmpty)
    }
    .preferredColorScheme(.dark)
}
