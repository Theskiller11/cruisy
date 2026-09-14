import SwiftUI

/// La riga con glifo, titolo, sottotitolo ed eventuale freccia.
///
/// La freccia compare solo se la riga porta davvero da qualche parte: una freccia su
/// una riga che non naviga è una promessa che l'interfaccia non mantiene.
struct InfoRow<Trailing: View>: View {
    let glyph: String
    let tint: Color
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.16)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Type.rowTitle)
                    .foregroundStyle(Palette.inkPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Type.rowDetail)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .glassSurface(cornerRadius: 20, prominence: .chip)
    }
}

extension InfoRow where Trailing == EmptyView {
    init(glyph: String, tint: Color, title: String, subtitle: String? = nil) {
        self.init(glyph: glyph, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// La freccia di navigazione, da mettere in coda a una riga che porta altrove.
struct Disclosure: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.inkTertiary)
            .accessibilityHidden(true)
    }
}
