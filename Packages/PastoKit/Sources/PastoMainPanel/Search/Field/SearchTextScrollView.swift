import AppKit

/// Scrolls the search field's text sideways. The text's focus ring is drawn around the scroll
/// view, so this is where the ring takes the shape of the whole field's capsule rather than of
/// the text area.
final class SearchTextScrollView: NSScrollView {
    /// The outline the focus ring follows, in the view's coordinates.
    var focusRingBounds = NSRect.zero {
        didSet {
            if focusRingBounds != oldValue { noteFocusRingMaskChanged() }
        }
    }

    override var focusRingMaskBounds: NSRect { focusRingBounds }

    override func drawFocusRingMask() {
        let radius = focusRingBounds.height / 2
        NSBezierPath(roundedRect: focusRingBounds, xRadius: radius, yRadius: radius).fill()
    }
}
