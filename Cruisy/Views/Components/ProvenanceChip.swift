import SwiftUI

/// Da dove viene l'orario che stai guardando.
///
/// Sta accanto a ogni countdown, sempre. Il brief aveva l'idea giusta ma la teneva
/// in un caso limite di un widget; qui è una regola: se l'app mostra un numero da cui
/// dipende il rientro a bordo di una persona, deve dire anche quanto si sta fidando
/// di sé stessa.
///
/// Glifo **e** parola, mai il solo colore.
struct ProvenanceChip: View {
    let origin: CountdownOrigin
    var freshness: Freshness?

    private var glyph: String {
        switch origin {
        case .publishedSchedule: "calendar"
        case .userEdited: "pencil"
        case .estimated: "wave.3.right"
        }
    }

    private var tint: Color {
        origin.isAuthoritative ? Palette.inkSecondary : Palette.ashore
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            // Ai corpi accessibili la pastiglia smette di funzionare: il testo va a
            // capo dentro la capsula e il monospaziato la fa larga quanto lo schermo.
            // Meglio perdere la forma che perdere la leggibilità — l'informazione
            // qui conta più della decorazione.
            plain
        } else {
            capsule
        }
    }

    private var plain: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: glyph)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Fonte dell'orario: \(text)"))
    }

    private var capsule: some View {
        HStack(spacing: 5) {
            Image(systemName: glyph)
                .font(.system(size: 9, weight: .semibold))
                .imageScale(.small)
            Text(text)
                .font(Type.technical)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassCapsule(prominence: .chip, tint: origin.isAuthoritative ? nil : Palette.ashore)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Fonte dell'orario: \(text)"))
    }

    private var text: String {
        guard let freshness, !origin.isAuthoritative else { return origin.label }
        return "\(origin.label) · \(freshness.label)"
    }
}

/// L'avviso che compare quando un dato è troppo vecchio per fidarsi.
struct StaleDataNotice: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ashore)
            Text(message)
                .font(Type.rowDetail)
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassSurface(cornerRadius: 16, prominence: .chip, tint: Palette.ashore)
        .accessibilityElement(children: .combine)
    }
}
