import SwiftUI

/// L'anello attorno al countdown.
///
/// Misura **lo stesso evento** del numero che abbraccia, e nient'altro. Nel brief
/// l'anello segnava la sosta in porto (09:00→18:00) mentre il numero contava all'all
/// aboard delle 17:30: due grandezze diverse messe una accanto all'altra, che è
/// esattamente il caso in cui serve un'etichetta per spiegare un controllo — e quando
/// serve un'etichetta, la mappatura è sbagliata.
///
/// Niente tacche per eventi successivi: farci stare anche la partenza vorrebbe dire
/// comprimere la scala, e l'anello smetterebbe di dire la verità sul numero che
/// contiene. La partenza è una riga di testo, sotto.
///
/// Si aggiorna al minuto, non al secondo: su un'attesa di ore lo spostamento di un
/// secondo è sotto la soglia percettiva, e ridisegnarlo di continuo costa soltanto.
struct ProgressRing<Content: View>: View {
    let countdown: Countdown
    let now: Date
    var lineWidth: CGFloat = 9
    var tint: Color = Palette.ashore
    @ViewBuilder var content: () -> Content

    private var progress: Double { countdown.progress(at: now) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.ink.opacity(0.14), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .fluid(Motion.settle, value: progress)

            content()
        }
        .accessibilityElement(children: .combine)
    }
}
