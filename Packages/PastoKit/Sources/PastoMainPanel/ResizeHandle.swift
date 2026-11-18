import AppKit

/// The strip along the panel's top edge that the user drags to change its height. Double-click
/// restores the default height.
final class ResizeHandle: NSView {
    var onLiveResize: ((_ proposedHeight: CGFloat) -> Void)?
    var onEndResize: (() -> Void)?
    var onReset: (() -> Void)?

    private struct Drag {
        let startY: CGFloat
        let startHeight: CGFloat
    }

    private static let resetClickCount = 2
    private var drag: Drag?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .frameResize(position: .top, directions: .all))
    }

    // Each handler lets the event continue up the responder chain first, so the main view can
    // hand keyboard focus back to the item strip.

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard let window else { return }
        drag = Drag(startY: event.locationInWindow.y, startHeight: window.frame.height)
        if event.clickCount == Self.resetClickCount {
            onReset?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard let drag else { return }
        // The window grows upwards from a fixed bottom edge, so window coordinates stay stable
        // while it resizes.
        onLiveResize?(drag.startHeight + event.locationInWindow.y - drag.startY)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        drag = nil
        if event.clickCount <= 1 {
            onEndResize?()
        }
    }
}
