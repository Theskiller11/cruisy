import SwiftUI
import UIKit

/// Il conto alla rovescia della Live Activity: ore e minuti finché manca più di
/// un'ora, e i secondi solo nell'ultima.
///
/// Sopra l'ora i secondi sono rumore: nella Dynamic Island un numero che cambia
/// sessanta volte al minuto attira l'occhio senza dire niente di utile — a tre ore
/// dall'all aboard nessuno ha bisogno di sapere che sono 2:59:52 e non 2:59:51.
/// Nell'ultima ora invece contano, e tornano.
///
/// ## Perché un taglio e non un formato
///
/// Un'attività in tempo reale non ricalcola niente da sé: le sole viste che si
/// aggiornano da sole sono `Text(timerInterval:)`, `ProgressView(timerInterval:)` e
/// i formati di sistema. Il timer di sistema ha sempre i secondi. I formati con la
/// precisione al minuto (`.timer(countingDownIn:maxPrecision:)`, `.offset(to:)`)
/// esistono, ma scrivono in lettere — «2 ore e 59 minuti» — che nella fessura
/// accanto alla fotocamera non entra. Verificato il 23 settembre 2026 stampandoli.
///
/// Quindi si usa il timer di sistema e se ne **mostra solo l'inizio**: il timer sta
/// in una cornice larga quanto «0:00:00», allineato a sinistra, e una seconda
/// cornice larga quanto «0:00» taglia fuori i secondi. Le due larghezze si misurano
/// con UIKit sullo stesso carattere, con le cifre a larghezza fissa. Il minuto
/// mostrato è quello **per difetto** (2:59:52 si legge 2:59), che per un rientro a
/// bordo è il verso giusto in cui sbagliare.
///
/// Il primo tentativo metteva il timer in un `.overlay` con `.fixedSize()` sopra una
/// sagoma invisibile: nell'app funziona, nel renderer delle Live Activity il timer
/// **non compare proprio**, né nell'isola né sulla schermata di blocco, nemmeno
/// senza il taglio. Cornici di larghezza finita invece sì: sono quelle che la vista
/// usava già.
///
/// Il passaggio all'ultima ora lo fa `urgent`, che nell'attività è
/// `context.isStale`: lo `staleDate` sta a un'ora dal traguardo, ed è l'unica
/// transizione che il sistema fa da solo, senza svegliare l'app.
///
/// Vale fino a 9:59 — con dieci ore la cornice sarebbe corta di una cifra. In porto
/// l'attività si accende nelle ultime tre ore, in mare nell'ultima ora e mezza.
public struct ActivityCountdown: View {
    let range: ClosedRange<Date>
    let urgent: Bool
    let size: CGFloat
    let weight: Font.Weight
    let alignment: HorizontalAlignment

    public init(range: ClosedRange<Date>, urgent: Bool, size: CGFloat,
                weight: Font.Weight = .black, alignment: HorizontalAlignment = .leading) {
        self.range = range
        self.urgent = urgent
        self.size = size
        self.weight = weight
        self.alignment = alignment
    }

    public var body: some View {
        let timer = Text(timerInterval: range, pauseTime: nil, countsDown: true, showsHours: true)
            .font(.system(size: size, weight: weight).width(.condensed))
            .monospacedDigit()
            .lineLimit(1)

        if urgent {
            // Nell'ultima ora il timer scrive «MM:SS», o «M:SS»: si mostra tutto,
            // allineato come vuole chi lo impagina. Nel secondo del passaggio può
            // ancora scrivere «1:00:00», e il sistema può arrivare allo `staleDate`
            // con qualche istante di ritardo: allora le cifre si stringono invece di
            // finire in «1:0…».
            timer
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .frame(width: width(of: "00:00") + 2, alignment: alignment == .trailing ? .trailing : .leading)
        } else {
            timer
                .multilineTextAlignment(.leading)
                .frame(width: width(of: "0:00:00") + 2, alignment: .leading)
                // Il taglio senza margine, anzi mezzo punto più stretto: con un
                // punto di troppo spuntavano i due puntini dei secondi, «3:15:».
                .frame(width: width(of: "0:00") - 0.5, alignment: .leading)
                .clipped()
        }
    }

    /// La larghezza di un testo nel carattere del conto. Il margine lo aggiunge chi
    /// la usa: al timer ne serve un filo, perché in una cornice larga esattamente
    /// quanto lui a volte va a capo; al taglio no.
    private func width(of sample: String) -> CGFloat {
        let base = UIFont.systemFont(ofSize: size, weight: Self.uiWeight(weight), width: .condensed)
        let tabular = base.fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]],
        ])
        let font = UIFont(descriptor: tabular, size: size)
        return (sample as NSString).size(withAttributes: [.font: font]).width
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .black: .black
        case .heavy: .heavy
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
    }
}
