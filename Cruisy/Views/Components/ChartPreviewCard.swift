import SwiftUI

/// La carta ridotta a card: mostra dove si è, e si tocca per aprirla a tutto schermo.
///
/// Esiste in due punti — nel pannello di Oggi, attorno alla nave, e nella schermata
/// d'attesa, su tutta la rotta — e deve essere **la stessa card**: porta alla stessa
/// carta, e due card leggermente diverse per la stessa destinazione sembrerebbero due
/// cose diverse.
struct ChartPreviewCard: View {
    let voyage: Voyage
    var fix: ShipFix?
    let now: Date
    var framing: SeaChart.Framing
    /// Cosa si sta guardando, detto come lo direbbe una persona.
    let title: String
    var showsPortNames = false
    var showsGraticule = false
    var height: CGFloat = 178

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SeaChart(voyage: voyage, fix: fix, now: now,
                     framing: framing,
                     showsPortNames: showsPortNames,
                     showsGraticule: showsGraticule)
                .frame(height: height)

            LinearGradient(colors: [.clear, Palette.abyss.opacity(0.85)],
                           startPoint: .center, endPoint: .bottom)

            HStack(alignment: .bottom) {
                Text(title)
                    .font(Type.rowTitle)
                    .foregroundStyle(Palette.inkPrimary)
                Spacer(minLength: 8)
                Text("Carta")
                    .font(Type.metricLabel.weight(.semibold))
                    .foregroundStyle(Palette.inkPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassCapsule(prominence: .chip)
            }
            .padding(14)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Palette.hairline, lineWidth: 0.5))
    }
}
