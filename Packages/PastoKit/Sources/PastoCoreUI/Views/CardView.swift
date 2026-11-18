import AppKit
import PastoUI

/// The building block of a card: a layer-backed view with a top-left origin, as the layout
/// tables are written, and an optional fill that follows the appearance.
///
/// Cards are laid out by hand: a view places its subviews in `layout()`, which runs again
/// whenever the view's size changes.
class CardView: LayerBackedView {
    /// The fill, or `nil` for none. Dynamic colours are resolved against the view's appearance.
    var fillColor: NSColor? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let isChange = newSize != frame.size
        super.setFrameSize(newSize)
        if isChange { needsLayout = true }
    }

    override func updateLayerColors() {
        layer?.backgroundColor = fillColor?.cgColor
    }
}
