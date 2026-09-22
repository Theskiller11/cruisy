import SwiftUI

/// L'avviso che si legge una volta sola, prima di fidarsi dei countdown.
///
/// Non è burocrazia. Questa app mostra un numero da cui dipende se una persona
/// riprende la nave o resta a terra in un paese straniero. Deve dire, una volta e
/// chiaramente, che cosa sa e che cosa non sa: gli orari li ha inseriti l'utente, e
/// la voce che fa fede è quella che parla dagli altoparlanti di bordo.
struct DisclaimerSheet: View {
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.livery) private var livery

    private struct Point: Identifiable {
        let id = UUID()
        let glyph: String
        let tint: Color
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private var points: [Point] { [
        Point(glyph: "megaphone.fill", tint: .orange,
              title: "Gli annunci di bordo fanno fede",
              body: "Cruisy conta a partire dagli orari che hai inserito tu. Se a bordo annunciano un orario diverso, quello vince: correggilo dal dettaglio del porto."),
        Point(glyph: "wifi.slash", tint: .green,
              title: "Funziona senza rete",
              body: "Carta e countdown si calcolano sul telefono. In mezzo all'oceano, in modalità aereo, continuano a funzionare."),
        Point(glyph: "clock.badge.exclamationmark.fill", tint: livery.tint,
              title: "Tutti gli orari sono in ora di bordo",
              body: "Le navi tengono la propria ora e non sempre la cambiano in porto. Se il tuo telefono non è allineato, Cruisy te lo dice."),
        Point(glyph: "lock.fill", tint: .green,
              title: "I tuoi dati restano qui",
              body: "Non c'è nessun account e nessun nostro server. Niente esce dal telefono da solo: l'itinerario si sposta soltanto se sei tu a mandarlo a qualcuno, e la tua posizione non esce mai."),
    ] }

    var body: some View {
        NavigationStack {
            ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prima di salpare")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("Come Cruisy calcola i suoi countdown, e che cosa non può sapere.")
                                .font(TicketType.rowDetail)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 12)

                        ForEach(points) { point in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: point.glyph)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(point.tint)
                                    .frame(width: 38, height: 38)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(point.tint.opacity(0.16)))
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(point.title)
                                        .font(TicketType.rowTitle)
                                        .foregroundStyle(.primary)
                                    Text(point.body)
                                        .font(TicketType.rowDetail)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onAccept()
                    dismiss()
                } label: {
                    Text("Ho capito")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(livery.tint)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        // Non si scarta trascinando: è una cosa da leggere, non una notifica.
        .interactiveDismissDisabled()
    }
}

#Preview {
    DisclaimerSheet {}
}
