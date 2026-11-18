import AppKit

/// The window of a detached preview, of an editor and of New Text Item: a floating utility panel
/// with a transparent title bar and no traffic lights, moved by dragging any empty part of it.
/// It is closed by its content — the close button of the header, Esc — or with ⌘W.
final class UtilityPanel: NSPanel {
    /// Called once the panel has closed, however it was closed. AppKit may still be finishing
    /// with it: whoever lets go of it here must keep it alive until the next turn.
    var onClose: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        animationBehavior = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        titlebarAppearsTransparent = true
        // Its owner gives it a title for VoiceOver and Mission Control; it is never drawn.
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        level = .floating
        // Windows created in code are released by ARC, not by closing.
        isReleasedWhenClosed = false
    }

    /// The panel is opened from the main panel, which does not activate Pasto: becoming key
    /// brings the application forward so that the editor really has the keyboard.
    override func becomeKey() {
        NSApp.activate(ignoringOtherApps: true)
        super.becomeKey()
    }

    override func close() {
        super.close()
        onClose?()
    }

    /// Sizes the panel to `view` and shows it as its content.
    func setContent(_ view: NSView) {
        let controller = NSViewController()
        controller.view = view
        controller.preferredContentSize = view.frame.size
        contentViewController = controller
        setContentSize(view.frame.size)
    }

    /// Gives the content another size, which its controller then asks for too.
    func resizeContent(to size: CGSize) {
        contentViewController?.preferredContentSize = size
        setContentSize(size)
    }
}
