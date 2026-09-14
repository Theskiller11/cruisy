import SwiftUI

/// Lo stato della nave in una pastiglia: in navigazione, in porto, sbarcati.
///
/// Colore **più** glifo **più** parola. Il brief affidava la distinzione al solo
/// colore (verde acqua contro ambra), che sparisce per chi non li distingue.
struct StatusPill: View {
    let moment: Voyage.Moment

    private var text: String {
        switch moment {
        case .beforeVoyage: String(localized: "Prima dell'imbarco", comment: "Stato del viaggio")
        case .inPort: String(localized: "In porto", comment: "Stato del viaggio")
        case .atSea: String(localized: "Giorno di mare", comment: "Stato del viaggio")
        case .completed: String(localized: "Sbarcati", comment: "Stato del viaggio")
        }
    }

    private var glyph: String {
        switch moment {
        case .beforeVoyage: "suitcase.rolling"
        case .inPort: "ferry"
        case .atSea: "water.waves"
        case .completed: "checkmark.seal"
        }
    }

    private var tint: Color {
        switch moment {
        case .inPort: Palette.ashore
        case .atSea: Palette.underway
        case .beforeVoyage, .completed: Palette.action
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(Type.metricLabel.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassCapsule(prominence: .chip, tint: tint)
        .accessibilityElement(children: .combine)
    }
}
