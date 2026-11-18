import AppKit
import PastoUI

/// The upper part of a link card: the page's preview image filling the area, or the site's icon
/// centred over a soft gradient.
final class LinkPreviewView: CardView {
    /// What stands for the page.
    enum Artwork {
        /// The page's preview image, across the whole area.
        case image(CGImage)
        /// The site's icon, or a square preview image, which is treated as one.
        case icon(CGImage)
        /// Nothing fetched yet, nothing to fetch, or a large image still being decoded: a
        /// generic symbol. There is no empty state between it and the artwork.
        case placeholder
    }

    var artwork = Artwork.placeholder {
        didSet { showArtwork() }
    }

    /// See `ImageScaling`; 0 makes the image always fill.
    var scaleToFillRatio: CGFloat {
        get { imageView.scaleToFillRatio }
        set { imageView.scaleToFillRatio = newValue }
    }

    /// How far below the centre the icon sits.
    var iconOffset: CGFloat = 0 {
        didSet {
            if iconOffset != oldValue { needsLayout = true }
        }
    }

    private let fadingView = GradientEffectView(frame: .zero)
    private let imageView = AdaptiveScalingImageView(frame: .zero)
    private let iconView = NSImageView()

    private static let placeholderSymbol = (
        NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: LinkCellMetrics.iconSide, weight: .regular))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fadingView.colors = .pair(top: CardColor.fallbackBackground, bottom: CardColor.linkGradientBottom)
        imageView.scaleToFillRatio = LinkCellMetrics.scaleToFillRatio

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        iconView.contentTintColor = CardColor.secondaryText
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = LinkCellMetrics.iconCornerRadius
        iconView.layer?.cornerCurve = .continuous
        iconView.layer?.masksToBounds = true

        addSubview(fadingView)
        addSubview(imageView)
        addSubview(iconView)
        showArtwork()
    }

    private func showArtwork() {
        switch artwork {
        case .image(let image):
            imageView.image = image
            iconView.image = nil
        case .icon(let icon):
            imageView.image = nil
            iconView.image = NSImage(cgImage: icon, size: CGSize(width: icon.width, height: icon.height))
        case .placeholder:
            imageView.image = nil
            iconView.image = Self.placeholderSymbol
        }
    }

    override func layout() {
        super.layout()
        fadingView.frame = bounds
        imageView.frame = bounds
        let side = LinkCellMetrics.iconSide
        iconView.frame = CGRect(
            x: (bounds.width - side) / 2, y: (bounds.height - side) / 2 + iconOffset, width: side, height: side
        )
    }
}
