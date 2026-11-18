import AppKit

/// Base class for Pasto's custom views: always layer-backed, redrawn only on demand, with a
/// single hook for colours that must follow light/dark appearance changes.
///
/// It updates its layer directly, so `draw(_:)` is never called: a subclass that draws must
/// override `wantsUpdateLayer` to return false.
open class LayerBackedView: NSView {
    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Pasto's views are created in code")
    }

    override open var wantsUpdateLayer: Bool { true }

    /// Called whenever layer properties derived from dynamic colours need refreshing. `CGColor`s
    /// do not adapt to appearance on their own, so subclasses assign them here.
    open func updateLayerColors() {}

    override open func updateLayer() {
        updateLayerColors()
    }

    override open func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
