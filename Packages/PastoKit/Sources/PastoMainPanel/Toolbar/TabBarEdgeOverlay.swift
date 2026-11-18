import AppKit

/// The line at an end of the tab strip that shows more tabs are hidden on that side: a vertical
/// gradient, clear at the top and the bottom and the label colour in the middle.
final class TabBarEdgeOverlay: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let middle = NSColor.labelColor.withAlphaComponent(TabBarMetrics.edgeOverlayOpacity)
        NSGradient(colors: [.clear, middle, .clear])?.draw(in: bounds, angle: -90)
    }

    /// The label colour follows the appearance.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
