import AppKit

/// Every layout number of a notice card and of the row of cards before the strip's first item.
public nonisolated struct NoticeCardMetrics: Equatable, Sendable {
    // MARK: Row of cards

    public static let rowLeadingInset: CGFloat = 24
    public static let cardSpacing: CGFloat = 24
    static let maximumCardWidth: CGFloat = 200
    static let minimumCardSide: CGFloat = 80

    /// A card is as tall as an item card and at most 200 pt wide.
    public static func cardSize(cellSide: CGFloat) -> CGSize {
        let side = max(cellSide, minimumCardSide)
        return CGSize(width: min(side, maximumCardWidth), height: side)
    }

    /// The width the row takes from the strip, which is where the first item then starts. No
    /// cards take no room.
    public static func rowWidth(cardCount: Int, cellSide: CGFloat) -> CGFloat {
        guard cardCount > 0 else { return 0 }
        let width = cardSize(cellSide: cellSide).width
        return rowLeadingInset + CGFloat(cardCount) * width + CGFloat(cardCount - 1) * cardSpacing
    }

    /// Where the card at `index` goes in the row, whose origin is its bottom leading corner.
    public static func cardFrame(at index: Int, cellSide: CGFloat) -> CGRect {
        let size = cardSize(cellSide: cellSide)
        return CGRect(
            origin: CGPoint(x: rowLeadingInset + CGFloat(index) * (size.width + cardSpacing), y: 0),
            size: size
        )
    }

    /// When cards arrive, leave or change places, the row moves them over this long, with the
    /// `Animator`'s default curve.
    public static let transitionDuration: TimeInterval = 0.35

    // MARK: Card, the same at every density

    static let cornerRadius: CGFloat = 16
    static let textLeadingInset: CGFloat = 12
    static let textTrailingInset: CGFloat = 16
    static let descriptionSpacing: CGFloat = 4
    static let buttonInset: CGFloat = 12
    static let fallbackSymbolName = "questionmark.square"
    static let closeSymbolName = "xmark"
    /// Of the label colour: black in the light appearance, white in the dark one.
    static let fillOpacity = 0.10
    /// The close button: a 12 pt glyph with 12 pt around it, pinned to the top trailing corner.
    static let closeSymbolPointSize: CGFloat = 12
    static let closeButtonSide: CGFloat = 36
    /// The glyph is the label colour at this opacity; while pressed, the secondary label colour
    /// (black at 0.5 or white at 0.55). The button has no fill in either state. With Increase
    /// Contrast on, the secondary label colour at rest and the label colour pressed.
    static let closeButtonOpacity = 0.26
    /// The action button's fill, of the label colour, at rest and pressed.
    static let buttonFillOpacity = 0.05
    static let buttonHighlightedFillOpacity = 0.10
    static let buttonContentInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

    /// Between the text and the button, at least.
    static let buttonTopSpacing: CGFloat = 8

    // MARK: Card, by density

    private(set) var iconInset: CGFloat
    private(set) var iconBoxSide: CGFloat
    let symbolPointSize: CGFloat
    private(set) var titleSpacing: CGFloat
    let textStyle: NSFont.TextStyle
    let buttonControlSize: NSControl.ControlSize

    init(sizeClass: SizeClass) {
        switch sizeClass {
        case .large, .regular, .small:
            iconInset = 12
            iconBoxSide = 28
            symbolPointSize = 22
            titleSpacing = 8
            textStyle = .title3
            buttonControlSize = .regular
        case .compact:
            iconInset = 10
            iconBoxSide = 20
            symbolPointSize = 15
            titleSpacing = 4
            textStyle = .body
            buttonControlSize = .small
        }
    }

    /// Part of the way from one density to another, for the strip's density transition: the
    /// geometry follows `progress`, while the type and the controls are the destination's from
    /// the start, as in an item card.
    static func blend(from source: Self, to destination: Self, progress: Double) -> Self {
        var blended = destination
        blended.iconInset = .interpolate(from: source.iconInset, to: destination.iconInset, progress: progress)
        blended.iconBoxSide = .interpolate(from: source.iconBoxSide, to: destination.iconBoxSide, progress: progress)
        blended.titleSpacing = .interpolate(from: source.titleSpacing, to: destination.titleSpacing, progress: progress)
        return blended
    }

    @MainActor var titleFont: NSFont { font(weight: .semibold) }
    @MainActor var descriptionFont: NSFont { font(weight: .medium) }

    @MainActor
    private func font(weight: NSFont.Weight) -> NSFont {
        .systemFont(ofSize: NSFont.preferredFont(forTextStyle: textStyle).pointSize, weight: weight)
    }
}
