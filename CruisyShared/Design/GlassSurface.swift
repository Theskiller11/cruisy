import SwiftUI

/// Il vetro di Cruisy, in un punto solo.
///
/// Due motivi per cui questo è un tipo e non uno stile copiato in ogni vista:
///
/// 1. "Riduci trasparenza" e "Aumenta contrasto" vanno onorati **ovunque**. Se il
///    vetro è scritto a mano in venti posti, prima o poi uno se ne dimentica.
/// 2. La regola dei materiali dice che una superficie grande deve leggersi come più
///    spessa di una piccola: blur più forte e ombra più profonda. Con un enum di
///    prominenza la gerarchia è dichiarata, non improvvisata.
public struct GlassSurface<S: Shape>: ViewModifier {

    /// Quanto pesa la superficie nella gerarchia. Cambia ombra e spessore del bordo.
    public enum Prominence: Sendable {
        /// Il pannello principale di una schermata: il countdown, la carta.
        case card
        /// Chrome che galleggia sopra il contenuto: barre, fogli.
        case chrome
        /// Pastiglie e chip piccoli.
        case chip

        var shadowRadius: CGFloat {
            switch self { case .card: 34; case .chrome: 26; case .chip: 10 }
        }
        var shadowY: CGFloat {
            switch self { case .card: 16; case .chrome: 10; case .chip: 4 }
        }
        var shadowOpacity: Double {
            switch self { case .card: 0.45; case .chrome: 0.40; case .chip: 0.24 }
        }
        /// Riempimento opaco usato quando la trasparenza è disattivata.
        var opaqueLift: Double {
            switch self { case .card: 0.10; case .chrome: 0.13; case .chip: 0.16 }
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private let shape: S
    private let prominence: Prominence
    private let tint: Color?

    public init(shape: S, prominence: Prominence = .card, tint: Color? = nil) {
        self.shape = shape
        self.prominence = prominence
        self.tint = tint
    }

    private var wantsHighContrast: Bool {
        contrast == .increased || DebugFlags.forcesIncreasedContrast
    }

    private var wantsOpaque: Bool {
        reduceTransparency || DebugFlags.forcesReducedTransparency
    }

    /// Il bordo che fa da "luce che prende il materiale". Si irrobustisce quando
    /// l'utente ha chiesto più contrasto, perché a quel punto il bordo è ciò che
    /// separa la superficie dal fondo.
    private var strokeColor: Color {
        wantsHighContrast ? Palette.ink.opacity(0.55) : Palette.hairline
    }
    private var strokeWidth: CGFloat { wantsHighContrast ? 1.5 : 0.5 }

    public func body(content: Content) -> some View {
        Group {
            if wantsOpaque || wantsHighContrast {
                // Niente sfocatura: un riempimento pieno, che resta leggibile
                // qualunque cosa scorra sotto.
                content.background(
                    shape.fill(Palette.sea)
                        .overlay(shape.fill(tint ?? Color.white).opacity(prominence.opaqueLift))
                )
            } else {
                content.glassEffect(
                    tint.map { Glass.regular.tint($0.opacity(0.22)) } ?? Glass.regular,
                    in: shape
                )
            }
        }
        .overlay(shape.stroke(strokeColor, lineWidth: strokeWidth))
        .shadow(color: Palette.abyss.opacity(prominence.shadowOpacity),
                radius: prominence.shadowRadius, x: 0, y: prominence.shadowY)
    }
}

public extension View {
    /// Posa il contenuto su una superficie di vetro con angoli arrotondati.
    func glassSurface(cornerRadius: CGFloat,
                      prominence: GlassSurface<RoundedRectangle>.Prominence = .card,
                      tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                              prominence: prominence, tint: tint))
    }

    /// Posa il contenuto su una pastiglia di vetro.
    func glassCapsule(prominence: GlassSurface<Capsule>.Prominence = .chip,
                      tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: Capsule(style: .continuous),
                              prominence: prominence, tint: tint))
    }
}
