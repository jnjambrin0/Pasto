import AppKit
import Symbols

/// Shows an SF Symbol centred the way a button centres its image: by the symbol's alignment
/// rect (the cap-height box it shares with text) rather than by its bounds, on whole pixels.
///
/// An image view would centre the bounds and round to whole points, which leaves glyphs half a
/// point away from where a button draws them.
///
/// Assistive technologies do not see it.
public final class SymbolView: NSView {
    public var symbol: SymbolDescription? {
        didSet {
            guard symbol != oldValue else { return }
            imageView.image = symbol?.makeImage()
            needsLayout = true
        }
    }

    public var tintColor: NSColor? {
        get { imageView.contentTintColor }
        set { imageView.contentTintColor = newValue }
    }

    private let imageView = NSImageView(frame: .zero)

    public init(symbol: SymbolDescription? = nil) {
        self.symbol = symbol
        super.init(frame: .zero)
        imageView.image = symbol?.makeImage()
        imageView.imageScaling = .scaleNone
        // A symbol is decoration: VoiceOver would read it as "image". A button that shows one
        // carries its own label.
        imageView.setAccessibilityElement(false)
        addSubview(imageView)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("SymbolView is created in code")
    }

    /// Size of the symbol's image, which includes the room symbols leave around their glyph.
    public var imageSize: NSSize {
        imageView.image?.size ?? .zero
    }

    /// Plays a one-off effect on the symbol, such as a bounce.
    public func addSymbolEffect(_ effect: some DiscreteSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default) {
        imageView.addSymbolEffect(effect, options: options, animated: true)
    }

    override public func layout() {
        super.layout()
        guard let image = imageView.image else { return }
        let origin = Self.imageOrigin(
            boundsSize: bounds.size,
            alignmentRect: image.alignmentRect,
            scale: window?.backingScaleFactor ?? 1
        )
        // Exactly the image's size, so the image view has no centring of its own left to do.
        imageView.frame = NSRect(origin: origin, size: image.size)
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    /// Where the image's bottom-left corner goes so that `alignmentRect` (in the image's
    /// coordinates) is centred in a view of `boundsSize`. Halves of a pixel round to the even one.
    nonisolated static func imageOrigin(boundsSize: CGSize, alignmentRect: CGRect, scale: CGFloat) -> CGPoint {
        func snapped(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded(.toNearestOrEven) / scale
        }
        return CGPoint(
            x: snapped(boundsSize.width / 2 - alignmentRect.midX),
            y: snapped(boundsSize.height / 2 - alignmentRect.midY)
        )
    }
}
