import AppKit

/// The capsule on an image card that states the size of the full image, such as "640 × 400".
final class ImageSizeLabel: CardView {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 6
        /// The label is 4 pt wider than its text, which makes the capsule that much wider.
        static let textSlack: CGFloat = 4
    }

    private let backdropView = BackdropView()
    private let label = NSTextField.cardLabel(font: .callout, color: .secondary, alignment: .center)
    private var labelSize = CGSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = ShortcutIndicatorMetrics.height / 2
        clipsToBounds = true
        addSubview(backdropView)
        addSubview(label)
    }

    /// Shows a size in points. The multiplication sign is not localized.
    func setSize(width: Int, height: Int) {
        label.stringValue = "\(width) × \(height)"
        let textSize = label.intrinsicContentSize
        labelSize = CGSize(width: textSize.width + Metrics.textSlack, height: textSize.height)
        needsLayout = true
    }

    /// The capsule's size: as tall as the shortcut indicator, as wide as its text plus padding.
    var capsuleSize: CGSize {
        CGSize(width: labelSize.width + 2 * Metrics.horizontalPadding, height: ShortcutIndicatorMetrics.height)
    }

    override func layout() {
        super.layout()
        backdropView.frame = bounds
        label.setAlignmentRect(CGRect(
            x: Metrics.horizontalPadding,
            y: (bounds.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        ))
    }
}
