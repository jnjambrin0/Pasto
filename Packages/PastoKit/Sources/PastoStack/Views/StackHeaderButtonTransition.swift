import SwiftUI

/// How a header button comes and goes: it only fades. The button learns when it has finished
/// arriving, to greet the user with a bounce of its symbol.
struct StackHeaderButtonTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .environment(\.isStackHeaderButtonShown, phase.isIdentity)
    }
}

extension EnvironmentValues {
    /// False while a header button is on its way in or out.
    @Entry var isStackHeaderButtonShown = true
}
