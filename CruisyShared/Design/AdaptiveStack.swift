import SwiftUI

/// Una riga che diventa una colonna quando il testo è grande.
///
/// Ai corpi accessibili una coppia "titolo + pastiglia" non ci sta più affiancata:
/// la pastiglia va a capo dentro sé stessa e diventa una macchia, e il titolo si
/// spezza con i trattini. La regola già usata per le metriche vale anche qui —
/// si scalano le altezze e si cambia impaginazione, non si stringono le larghezze.
///
/// Esiste come tipo perché il caso si ripete in ogni testata dell'app, e cinque
/// controlli di `dynamicTypeSize` copiati a mano sono cinque occasioni di
/// dimenticarne uno.
struct AdaptiveHStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: horizontalAlignment, spacing: spacing, content: content)
        } else {
            HStack(alignment: verticalAlignment, spacing: spacing, content: content)
        }
    }
}

extension View {
    /// Uno spaziatore che sparisce quando la riga è diventata una colonna: in
    /// verticale spingerebbe gli elementi ai due capi dello schermo.
    @ViewBuilder
    func adaptiveSpacer() -> some View { self }
}

/// Spaziatore che si annulla ai corpi accessibili.
struct AdaptiveSpacer: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var minLength: CGFloat = 8

    var body: some View {
        if !typeSize.isAccessibilitySize {
            Spacer(minLength: minLength)
        }
    }
}
