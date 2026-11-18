import AppKit
import FoundationModels

/// The system's Writing Tools, reached through the standard responder action rather than a
/// coordinator of our own.
enum WritingTools {
    /// Whether the system can offer them now: the on-device model is there and ready.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { true } else { false }
    }

    /// The button that opens them, or `nil` when they are not available. It has no title and
    /// no tooltip.
    static func makeButton() -> PreviewButton? {
        guard isAvailable else { return nil }
        let button = PreviewButton(symbolName: "apple.writing.tools", accessibilityLabel: PreviewStrings.writingTools)
        button.onClick = { show(from: $0) }
        return button
    }

    /// Asks the first responder — the text being edited — to show Writing Tools, after giving
    /// an editor that is just opening the time to take focus.
    static func show(from sender: Any?) {
        Task {
            // A cancelled wait still shows them, only sooner.
            try? await Task.sleep(for: PreviewMetrics.writingToolsDelay)
            NSApp.sendAction(#selector(NSResponder.showWritingTools(_:)), to: nil, from: sender)
        }
    }
}
