import AppKit

/// The card of a colour: the whole card is the colour, with its hexadecimal value in the middle.
///
/// The value is dark on light colours and light on dark ones, because the card's appearance
/// follows its fill (`ColorCode.isLight`). In the compact density, where the header has no band,
/// the colour reaches the top of the card.
public final class ColorItemCell: ItemCell {
    private let colorLabel = NSTextField.cardLabel(font: .colorCode, color: .primary, alignment: .center)
    private var labelSize = CGSize.zero

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bodyView.addSubview(colorLabel)
    }

    override var isCompactContentFullSize: Bool { true }
    override var preferredCompactHeaderStyle: HeaderLayout.CompactStyle? { .transparent }

    override func configureContent(with model: ItemCellModel, environment: ItemCellEnvironment) {
        guard case .color(let color) = model.content else {
            colorLabel.stringValue = ""
            cardBackground = .standard
            return
        }
        cardBackground = .color(color)
        colorLabel.stringValue = color.hexString
        labelSize = colorLabel.intrinsicContentSize
    }

    override func layoutContent(in bounds: CGRect) {
        colorLabel.setAlignmentRect(CGRect(
            x: (bounds.width - labelSize.width) / 2,
            y: (bounds.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        ))
    }
}
