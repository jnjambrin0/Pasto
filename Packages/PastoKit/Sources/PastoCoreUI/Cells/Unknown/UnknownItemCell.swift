import AppKit
import PastoUI

/// The card of an item whose content has no preview: a warning symbol and a caption. The item
/// itself is intact and can still be pasted.
public final class UnknownItemCell: ItemCell {
    private enum Metrics {
        static let symbolPointSize: CGFloat = 32
        /// Gap between the symbol's area and the caption.
        static let captionSpacing: CGFloat = 10
    }

    private let imageView = NSImageView()
    private let captionLabel = NSTextField.cardLabel(font: .callout, color: .secondary, alignment: .center)
    private var imageTopInset = CardContentMetrics.topInset

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let symbol = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)
        imageView.image = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: Metrics.symbolPointSize, weight: .regular)
        )
        imageView.contentTintColor = CardColor.secondaryText
        captionLabel.stringValue = CardStrings().previewUnavailable

        bodyView.addSubview(imageView)
        bodyView.addSubview(captionLabel)
    }

    /// The only density-dependent value is set outright, never blended.
    override func applyContentLayout(for sizeClass: SizeClass) {
        imageTopInset = sizeClass == .compact ? 0 : CardContentMetrics.topInset
    }

    override func layoutContent(in bounds: CGRect) {
        // The caption is centred on the row of the shortcut indicator.
        let captionHeight = captionLabel.intrinsicContentSize.height
        let captionTop = bounds.height - ShortcutIndicatorMetrics.centerFromCardBottom - captionHeight / 2
        captionLabel.setAlignmentRect(CGRect(x: 0, y: captionTop, width: bounds.width, height: captionHeight))

        let inset = CardContentMetrics.sideInset
        imageView.frame = CGRect(
            x: inset,
            y: imageTopInset,
            width: max(bounds.width - 2 * inset, 0),
            height: max(captionTop - Metrics.captionSpacing - imageTopInset, 0)
        )
    }
}
