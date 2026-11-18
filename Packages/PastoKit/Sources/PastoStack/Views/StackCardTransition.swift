import SwiftUI

/// How a card comes into the list and leaves it: slightly smaller, blurred, shifted down and
/// transparent, the same both ways. With "Reduce Motion" only the fade is left.
struct StackCardTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(Effect(isIdentity: phase.isIdentity))
    }

    private struct Effect: ViewModifier {
        let isIdentity: Bool
        @Environment(\.accessibilityReduceMotion) private var reducesMotion

        func body(content: Content) -> some View {
            let moves = !isIdentity && !reducesMotion
            content
                .scaleEffect(moves ? StackMetrics.Motion.transitionScale : 1)
                .blur(radius: moves ? StackMetrics.Motion.transitionBlurRadius : 0)
                .offset(y: moves ? StackMetrics.Motion.transitionOffset : 0)
                .opacity(isIdentity ? 1 : 0)
        }
    }
}
