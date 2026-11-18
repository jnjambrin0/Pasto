import AppKit
import PastoUI
import SwiftUI
import Symbols

/// A button of the stack's header: the toolbar button of the main panel, hosted in SwiftUI.
///
/// It is an AppKit view on purpose. It works while Pasto is not the active application, it can
/// hang a menu from itself, and the window can tell it apart from the surface that drags the panel.
struct StackHeaderButton: NSViewRepresentable {
    enum Behavior {
        case action(() -> Void)
        case menu(() -> NSMenu)
    }

    final class Coordinator {
        /// Whether the button was fully there the last time it was updated.
        var wasShown = true
    }

    let symbolName: String
    let label: String
    let behavior: Behavior

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ToolbarButton {
        let symbol = SymbolDescription(symbolName, pointSize: StackMetrics.Header.buttonSymbolSize, weight: .medium)
        let button = ToolbarButton(size: .medium, symbol: symbol, accessibilityLabel: label)
        // The menu hangs below the button. The button's y grows upwards.
        button.menuOrigin = { NSPoint(x: 0, y: -StackMetrics.Header.menuGap) }
        return button
    }

    func updateNSView(_ button: ToolbarButton, context: Context) {
        switch behavior {
        case .action(let action):
            button.onClick = action
            button.menuProvider = nil
        case .menu(let provider):
            button.onClick = nil
            button.menuProvider = provider
        }

        // A button that has just finished arriving bounces its symbol once.
        let isShown = context.environment.isStackHeaderButtonShown
        if isShown, !context.coordinator.wasShown, !context.environment.accessibilityReduceMotion {
            button.addSymbolEffect(BounceSymbolEffect.bounce.up.byLayer, options: .nonRepeating)
        }
        context.coordinator.wasShown = isShown
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ToolbarButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
