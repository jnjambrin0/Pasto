import AppKit

/// What the item strip says in place of cards while it has none: that the list is empty, that a
/// search is running or that it found nothing. One line of large, faint text a little above the
/// middle of the strip, which appears and goes away at once.
final class ListPlaceholderView: NSView {
    var text: String {
        get { label.stringValue }
        set {
            guard newValue != label.stringValue else { return }
            label.stringValue = newValue
            needsLayout = true
        }
    }

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = MainPanelMetrics.emptyTextFont
        label.textColor = MainPanelMetrics.emptyTextColor
        addSubview(label)

        // The colour depends on Increase Contrast too.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    /// Whatever thread the notification comes on, the text changes on the main one.
    @objc private nonisolated func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
        Task { @MainActor in label.textColor = MainPanelMetrics.emptyTextColor }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ListPlaceholderView is created in code")
    }

    override func layout() {
        super.layout()
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(
            x: ((bounds.width - label.frame.width) / 2).rounded(),
            y: (MainPanelMetrics.emptyTextCenterY(in: bounds) - label.frame.height / 2).rounded()
        ))
    }

    /// The text is not a target: clicks go to the strip under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
