import AppKit

/// A vertical two-stop gradient.
final class GradientEffectView: CardView {
    enum Colors {
        /// From one colour at the top to another at the bottom.
        case pair(top: NSColor, bottom: NSColor)
        /// From nothing at the top to the colour at the bottom, without passing through any
        /// other hue on the way.
        case fade(to: NSColor)
    }

    /// Dynamic colours are resolved against the view's appearance.
    var colors = Colors.pair(top: .clear, bottom: .clear) {
        didSet { needsDisplay = true }
    }

    private let gradientLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The gradient follows the view at once: it must not lag behind a resize or cross-fade
        // between colours.
        gradientLayer.actions = ["bounds": NSNull(), "position": NSNull(), "colors": NSNull()]
        layer?.addSublayer(gradientLayer)
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    override func updateLayerColors() {
        super.updateLayerColors()
        switch colors {
        case .pair(let top, let bottom):
            gradientLayer.colors = [top.cgColor, bottom.cgColor]
        case .fade(let color):
            let opaque = color.cgColor
            gradientLayer.colors = [opaque.copy(alpha: 0) ?? opaque, opaque]
        }
    }
}
