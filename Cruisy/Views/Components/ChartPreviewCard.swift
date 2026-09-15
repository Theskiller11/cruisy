import SwiftUI

/// La carta ridotta a cartolina: mostra dove si è, e si tocca per aprirla.
///
/// Non è un'immagine: è lo stesso disegnatore della schermata a tutto schermo,
/// con meno dettagli. Così l'anteprima non può mai raccontare una posizione
/// diversa da quella vera. La cornice di carta la fa stare nel linguaggio del
/// biglietto: un ritaglio di carta nautica spillato al biglietto.
struct ChartPreviewCard: View {
    @Environment(\.livery) private var livery
    let voyage: Voyage
    var fix: ShipFix?
    let now: Date
    var framing: SeaChart.Framing
    /// Cosa si sta guardando, detto come lo direbbe una persona.
    let title: String
    var showsPortNames = false
    var showsGraticule = false
    var height: CGFloat = 168

    var body: some View {
        VStack(spacing: 0) {
            SeaChart(voyage: voyage, fix: fix, now: now,
                     framing: framing,
                     showsPortNames: showsPortNames,
                     showsGraticule: showsGraticule)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(6)

            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(TicketType.rowTitle)
                    .foregroundStyle(livery.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("Carta").ticketFieldLabel(livery.field)
                    PaperDisclosure()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .padding(.top, 4)
        }
        .paperCard()
    }
}
