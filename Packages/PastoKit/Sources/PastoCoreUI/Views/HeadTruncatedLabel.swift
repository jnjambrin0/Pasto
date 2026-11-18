import AppKit

/// A label that drops the beginning of a text that does not fit, instead of the end: for file
/// paths (`HeadTruncation`).
final class HeadTruncatedLabel: NSTextField {
    /// The whole text. What is shown may be shorter; then the tooltip carries all of it.
    var fullText = "" {
        didSet {
            if fullText != oldValue { fittedWidth = nil }
        }
    }

    private var fittedWidth: CGFloat?
    private var fittedHeight: CGFloat = 0
    private lazy var slashWidth = ("/" as NSString).size(withAttributes: [.font: font as Any]).width

    init(font: CardFont, color: CardTextColor, maximumNumberOfLines: Int) {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        self.font = font.font
        textColor = color.color
        alignment = .center
        // Lines break between words, which in a path means after a "/", so a path breaks by its
        // components; what does not fit in the last line is left out, without an ellipsis.
        lineBreakMode = .byWordWrapping
        self.maximumNumberOfLines = maximumNumberOfLines
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HeadTruncatedLabel is created in code")
    }

    /// Cuts the text for a label whose alignment rectangle is `width` wide and returns the
    /// height it then needs. The result is remembered, so calling this on every layout pass
    /// only measures when something changed.
    func fit(toWidth width: CGFloat) -> CGFloat {
        if fittedWidth == width { return fittedHeight }

        // The estimate uses the label's whole width, cell padding included.
        let insets = alignmentRectInsets
        let capacity = HeadTruncation.capacity(
            lines: maximumNumberOfLines, width: width + insets.left + insets.right, characterWidth: slashWidth
        )
        let displayed = HeadTruncation.truncate(fullText, capacity: capacity)
        stringValue = displayed
        toolTip = displayed == fullText ? nil : fullText

        fittedWidth = width
        fittedHeight = textHeight(forWidth: width)
        return fittedHeight
    }
}
