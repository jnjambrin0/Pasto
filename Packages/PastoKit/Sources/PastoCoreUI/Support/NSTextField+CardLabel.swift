import AppKit

extension NSTextField {
    /// A static label in a card. Its frame is always set by hand, with `setAlignmentRect(_:)`.
    static func cardLabel(font: CardFont, color: CardTextColor, alignment: NSTextAlignment = .natural) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font.font
        label.textColor = color.color
        label.alignment = alignment
        return label
    }

    /// The height Auto Layout would give the label when its alignment rectangle is `width`
    /// wide: that of its text wrapped to that width, within its line limit.
    func textHeight(forWidth width: CGFloat) -> CGFloat {
        preferredMaxLayoutWidth = width
        return intrinsicContentSize.height
    }

    /// Offers `help` as the label's tooltip: a text other than the label's own always; the
    /// label's own text only while the label is too small for it. To be called again whenever
    /// the label's frame changes.
    func setAdaptiveToolTip(_ help: String?) {
        guard let help, help == stringValue else {
            toolTip = help
            return
        }
        preferredMaxLayoutWidth = bounds.width
        let fitting = fittingSize
        toolTip = bounds.width * bounds.height < fitting.width * fitting.height ? help : nil
    }
}

extension NSView {
    /// Places the view where Auto Layout would for the same numbers. The cards' layout constants
    /// are alignment rectangles: a text field's frame is 2 pt wider on each side, so that its text
    /// starts exactly at the alignment rectangle's edge.
    func setAlignmentRect(_ rect: CGRect) {
        frame = frame(forAlignmentRect: rect)
    }
}
