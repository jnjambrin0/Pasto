import AppKit

/// The bottom of a link card: the page's title over its address.
///
/// With link previews on it is two single lines (the address takes two when there is no title
/// yet) and the address is shortened. With previews off it is the whole card: up to three lines
/// of title and the full address below.
final class LinkFooterView: CardView {
    private let titleLabel = NSTextField.cardLabel(font: .bodySemibold, color: .primary)
    private let urlLabel = NSTextField.cardLabel(font: .callout, color: .secondary)

    /// The help each label offers when it is cut short, or always if it says more.
    private var titleHelp: String?
    private var urlHelp: String?
    private var measuredWidth: CGFloat?
    private var titleHeight: CGFloat = 0
    private var urlHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.lineBreakMode = .byWordWrapping
        urlLabel.lineBreakMode = .byCharWrapping
        for label in [titleLabel, urlLabel] {
            label.cell?.truncatesLastVisibleLine = true
            // The letters are squeezed a little before a line is cut.
            label.allowsDefaultTighteningForTruncation = true
        }
        addSubview(titleLabel)
        addSubview(urlLabel)
    }

    func configure(title: String?, url: URL, isPreviewEnabled: Bool) {
        titleLabel.isHidden = title == nil
        titleLabel.stringValue = title ?? ""
        titleHelp = title
        titleLabel.maximumNumberOfLines = isPreviewEnabled ? 1 : 3

        urlLabel.stringValue = isPreviewEnabled ? ShortURL.string(for: url) : url.absoluteString
        urlHelp = url.absoluteString
        urlLabel.maximumNumberOfLines = isPreviewEnabled ? (title == nil ? 2 : 1) : 0
        updateToolTips()

        measuredWidth = nil
        needsLayout = true
    }

    /// The height the footer takes when it is `width` wide: its text plus padding.
    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        measure(forWidth: width)
        let spacing = titleLabel.isHidden ? 0 : LinkCellMetrics.footerSpacing
        return 2 * LinkCellMetrics.footerVerticalPadding + titleHeight + spacing + urlHeight
    }

    /// Text heights only change with the content or the width, so they are measured once for both.
    private func measure(forWidth width: CGFloat) {
        guard measuredWidth != width else { return }
        measuredWidth = width
        let textWidth = max(width - 2 * CardContentMetrics.sideInset, 0)
        titleHeight = titleLabel.isHidden ? 0 : titleLabel.textHeight(forWidth: textWidth)
        urlHeight = urlLabel.textHeight(forWidth: textWidth)
    }

    override func layout() {
        super.layout()
        measure(forWidth: bounds.width)
        let inset = CardContentMetrics.sideInset
        let textWidth = max(bounds.width - 2 * inset, 0)
        var y = LinkCellMetrics.footerVerticalPadding

        if !titleLabel.isHidden {
            titleLabel.setAlignmentRect(CGRect(x: inset, y: y, width: textWidth, height: titleHeight))
            y += titleHeight + LinkCellMetrics.footerSpacing
        }
        // The address takes what is left, which only exceeds its text when the footer is the
        // whole card.
        let room = bounds.height - LinkCellMetrics.footerVerticalPadding - y
        urlLabel.setAlignmentRect(CGRect(x: inset, y: y, width: textWidth, height: max(min(urlHeight, room), 0)))
        updateToolTips()
    }

    private func updateToolTips() {
        titleLabel.setAdaptiveToolTip(titleHelp)
        urlLabel.setAdaptiveToolTip(urlHelp)
    }
}
