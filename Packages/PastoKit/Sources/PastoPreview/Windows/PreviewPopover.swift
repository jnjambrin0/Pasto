import AppKit
import PastoCore
import PastoFoundation

/// The preview Space opens: a transient popover anchored to the item's card, which leaves the
/// keyboard with the strip of cards. Its look — material, arrow, shadow — is the system's.
///
/// While it is open it follows the strip's selection, showing each item in turn in the same
/// popover. It is discarded when it closes.
final class PreviewPopover: NSPopover, NSPopoverDelegate {
    /// Called once the popover is on its way out: about to close, or dragged off into a window.
    var onWillClose: (() -> Void)?
    /// Supplies the window the preview moves to when the user drags the popover away.
    var detachedWindowProvider: (() -> NSWindow?)?

    private(set) var previewView: ItemPreviewView
    /// The view the popover was shown over.
    private(set) weak var anchor: NSView?
    private let config: ConfigStore
    private var sharingVisibility: Task<Void, Never>?

    /// The item on show.
    var itemID: ItemID { previewView.item.id }

    init(previewView: ItemPreviewView, config: ConfigStore) {
        self.previewView = previewView
        self.config = config
        super.init()

        behavior = .transient
        animates = true
        delegate = self
        setContent(previewView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PreviewPopover is created in code")
    }

    private func setContent(_ view: ItemPreviewView) {
        let controller = NSViewController()
        controller.view = view
        controller.preferredContentSize = view.frame.size
        contentViewController = controller
    }

    /// Shows the popover over `anchor`, preferring the side above it, and hands the keyboard
    /// back to the anchor's window. The first time it appears animated; from then on it no
    /// longer animates while it stays open.
    func show(anchoredTo anchor: NSView) {
        let wasShown = isShown
        self.anchor = anchor
        // The edge is named in the anchor's coordinates, where "up" depends on its flipping.
        show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .minY : .maxY)
        animates = false
        // The panel's window answers `nil` by restoring its initial first responder, the strip.
        anchor.window?.makeFirstResponder(nil)
        // The keyboard stays on the strip, so VoiceOver would not notice the preview: it says
        // it opened. Moving to another item keeps it quiet.
        if !wasShown {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: PreviewStrings.previewWindowTitle, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
            )
        }
    }

    /// Shows another item in the open popover, over `anchor`: the content and its size change at
    /// once, in the same window.
    func show(_ previewView: ItemPreviewView, anchoredTo anchor: NSView) {
        // An edit of the old title ends, and is kept, as it would be if the popover closed.
        self.previewView.window?.makeFirstResponder(nil)
        self.previewView = previewView
        setContent(previewView)
        show(anchoredTo: anchor)
    }

    /// The frame of the preview on screen, where an editing window takes its place.
    var contentScreenFrame: NSRect? {
        previewView.window?.convertToScreen(previewView.convert(previewView.bounds, to: nil))
    }

    /// Closes without the content being seen to go: the window that replaces it is already
    /// about to show in the same place.
    func closeInvisibly() {
        previewView.window?.alphaValue = 0
        close()
    }

    /// "Show During Screen Sharing" applies to the popover's window too: before it is first
    /// seen, so that a hidden preview never shows in a shared screen, and then whenever the
    /// setting changes while the popover is open.
    private func followSharingVisibility() {
        sharingVisibility?.cancel()
        applySharingVisibility(config.value(for: .isScreenSharingContentVisible))
        sharingVisibility = Task { [weak self, config] in
            // The stream starts with the value just applied; applying it again changes nothing.
            for await isVisible in config.values(for: .isScreenSharingContentVisible) {
                guard let self else { return }
                applySharingVisibility(isVisible)
            }
        }
    }

    private func applySharingVisibility(_ isVisible: Bool) {
        previewView.window?.sharingType = isVisible ? .readOnly : .none
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        followSharingVisibility()
    }

    /// Closing first lets the popover animate again; whether this closing is then animated is
    /// AppKit's decision.
    func popoverWillClose(_ notification: Notification) {
        animates = true
        retire()
    }

    func popoverDidDetach(_ popover: NSPopover) {
        retire()
    }

    private func retire() {
        sharingVisibility?.cancel()
        onWillClose?()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        true
    }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        detachedWindowProvider?()
    }
}
