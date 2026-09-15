import SwiftUI

/// Lo stato iniziale: nessuna crociera inserita.
///
/// Niente dati finti a riempire il vuoto. Un'app che si presenta con una crociera
/// inventata addosso è contenuto segnaposto, e non supera la revisione. Il posto
/// del biglietto è un biglietto vuoto, tratteggiato: si capisce cosa ci andrà.
struct NoVoyageView: View {
    @Environment(VoyageStore.self) private var store
    @Environment(\.livery) private var livery
    @State private var isEditing = false
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "ticket")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(livery.onHullMuted)
                Text("Nessuna crociera")
                    .font(TicketType.place)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.onHull)
                Text("Incolla o fotografa la conferma della compagnia: Cruisy ne ricava l'itinerario e da lì calcola i countdown, anche senza rete a bordo.")
                    .font(TicketType.rowDetail)
                    .foregroundStyle(livery.onHullMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(livery.onHull.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])))

            VStack(spacing: 10) {
                Button {
                    isImporting = true
                } label: {
                    Label("Importa l'itinerario", systemImage: "text.viewfinder")
                        .font(TicketType.rowTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .tint(livery.signal)

                Button("Inserisci a mano") { isEditing = true }
                    .font(TicketType.rowTitle)
                    .tint(livery.onHull)
            }
        }
        .padding(.horizontal, 28)
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
        Livery.cruisy.hull.ignoresSafeArea()
        NoVoyageView().environment(VoyageStore.previewEmpty)
    }
    .preferredColorScheme(.dark)
}
