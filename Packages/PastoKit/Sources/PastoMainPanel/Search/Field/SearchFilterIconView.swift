import AppKit
import PastoUI

/// Draws a filter's icon in whatever square it is given: a symbol or an application's icon
/// scaled down to fit, or a pinboard's dot of fixed size, centred.
final class SearchFilterIconView: LayerBackedView {
    /// What the system is asked for when it has no symbol with the icon's name.
    private static let missingSymbolName = "questionmark.square"

    var icon: SearchFilterIcon {
        didSet {
            if icon != oldValue { showIcon() }
        }
    }

    /// The colour symbols are drawn in. An application's icon and a pinboard's dot keep theirs.
    var tintColor: NSColor {
        get { imageView.contentTintColor ?? .labelColor }
        set { imageView.contentTintColor = newValue }
    }

    private let imageView = NSImageView(frame: .zero)
    private let dotView = NSView(frame: .zero)

    init(icon: SearchFilterIcon) {
        self.icon = icon
        super.init(frame: .zero)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        // Decoration next to the filter's name, which is what VoiceOver reads.
        imageView.setAccessibilityElement(false)
        addSubview(imageView)
        dotView.wantsLayer = true
        addSubview(dotView)
        showIcon()
    }

    private func showIcon() {
        switch icon {
        case .symbol(let name):
            imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: Self.missingSymbolName, accessibilityDescription: nil)
        case .image(let data):
            imageView.image = NSImage(data: data)
        case .pinboardDot, .none:
            imageView.image = nil
        }
        if case .pinboardDot = icon {
            dotView.isHidden = false
        } else {
            dotView.isHidden = true
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        let dotSide = min(SearchMetrics.pinboardDotSide, bounds.width, bounds.height)
        dotView.frame = NSRect(
            x: bounds.midX - dotSide / 2,
            y: bounds.midY - dotSide / 2,
            width: dotSide,
            height: dotSide
        )
        dotView.layer?.cornerRadius = dotSide / 2
    }

    override func updateLayerColors() {
        if case .pinboardDot(let color) = icon {
            dotView.layer?.backgroundColor = color.displayColor.cgColor
        }
    }
}
