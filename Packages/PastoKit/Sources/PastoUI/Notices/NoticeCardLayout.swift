import CoreGraphics

/// Where the parts of a notice card go, in the card's flipped coordinates (origin at the top
/// leading corner).
nonisolated struct NoticeCardLayout: Equatable {
    let icon: CGRect
    let closeButton: CGRect
    let title: CGRect
    /// Empty when the text above leaves no room for it.
    let description: CGRect
    let button: CGRect

    /// - Parameters:
    ///   - titleHeight: The height the title takes at the text width.
    ///   - descriptionHeight: The same for the description; 0 without one.
    init(
        size: CGSize,
        metrics: NoticeCardMetrics,
        titleHeight: CGFloat,
        descriptionHeight: CGFloat,
        buttonHeight: CGFloat
    ) {
        typealias Fixed = NoticeCardMetrics

        icon = CGRect(x: metrics.iconInset, y: metrics.iconInset, width: metrics.iconBoxSide, height: metrics.iconBoxSide)
        closeButton = CGRect(
            x: size.width - Fixed.closeButtonSide,
            y: 0,
            width: Fixed.closeButtonSide,
            height: Fixed.closeButtonSide
        )

        button = CGRect(
            x: Fixed.buttonInset,
            y: size.height - Fixed.buttonInset - buttonHeight,
            width: size.width - 2 * Fixed.buttonInset,
            height: buttonHeight
        )

        // The text gets what is left between the icon and the button; the title comes first.
        let textWidth = size.width - Fixed.textLeadingInset - Fixed.textTrailingInset
        let textBottom = button.minY - Fixed.buttonTopSpacing
        let titleTop = icon.maxY + metrics.titleSpacing
        title = CGRect(
            x: Fixed.textLeadingInset,
            y: titleTop,
            width: textWidth,
            height: max(min(titleHeight, textBottom - titleTop), 0)
        )
        let descriptionTop = title.maxY + Fixed.descriptionSpacing
        description = CGRect(
            x: Fixed.textLeadingInset,
            y: descriptionTop,
            width: textWidth,
            height: max(min(descriptionHeight, textBottom - descriptionTop), 0)
        )
    }
}
