import CoreGraphics

/// Dimensions of the shortcut indicator.
nonisolated enum ShortcutIndicatorMetrics {
    static let height: CGFloat = 18
    /// Distance to the card's trailing and bottom edges.
    static let cardInset: CGFloat = 8
    static let horizontalPadding: CGFloat = 6
    /// Gap between the glyph and the number when both show.
    static let spacing: CGFloat = 4
    static let glyphAlpha: CGFloat = 0.65

    /// The row at the bottom of a card that the indicator defines. Captions and badges of the
    /// content line up with it: `S − 26` to `S − 8`, centred on `S − 17`.
    static let centerFromCardBottom = cardInset + height / 2
}
