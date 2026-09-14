import SwiftUI

/// Il contratto di movimento, deciso una volta e riusato ovunque.
///
/// Il brief era statico: nessuna specifica di animazione. I valori qui vengono dalla
/// tabella di *Designing Fluid Interfaces*: smorzamento critico come impostazione
/// predefinita, rimbalzo **solo** dove il gesto dell'utente ha già portato slancio.
public enum Motion {

    /// Cambi di stato e di rotta: arriva e si ferma, senza rimbalzare.
    /// Un rimbalzo su qualcosa che è solo comparso in dissolvenza è fuori luogo.
    public static let settle = Animation.spring(response: 0.35, dampingFraction: 1.0)

    /// Fogli e drawer, trascinabili: un filo di slancio perché il dito ce l'ha messo.
    public static let sheet = Animation.spring(response: 0.30, dampingFraction: 0.80)

    /// Ingrandimento della carta dalla card e ritorno: stesso percorso all'andata
    /// e al ritorno (§N dell'audit).
    public static let zoom = Animation.spring(response: 0.42, dampingFraction: 0.86)

    /// Reazione immediata alla pressione, prima del rilascio.
    public static let press = Animation.easeOut(duration: 0.12)

    /// Sostituto per chi ha chiesto meno movimento: una dissolvenza, non l'assenza
    /// di feedback.
    public static let reduced = Animation.easeInOut(duration: 0.20)

    /// L'animazione giusta viste le preferenze di sistema.
    public static func honouring(_ reduceMotion: Bool, _ animation: Animation) -> Animation {
        reduceMotion ? reduced : animation
    }
}

public extension View {
    /// Applica un'animazione che decade a dissolvenza quando "Riduci movimento" è attivo.
    func fluid<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(FluidAnimation(animation: animation, value: value))
    }
}

private struct FluidAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.honouring(reduceMotion, animation), value: value)
    }
}
