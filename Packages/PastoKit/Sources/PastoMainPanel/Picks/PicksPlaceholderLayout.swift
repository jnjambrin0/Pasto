import CoreGraphics

/// Where the elements of the screen recording block go: a centred column of the icon, the
/// title, the subtitle and a row of two buttons, a little above the middle of the strip. Frames
/// are in a non-flipped space, origin at the bottom-left corner, and whole points.
nonisolated struct PicksPlaceholderLayout: Equatable {
    struct Sizes {
        var icon: CGSize
        var title: CGSize
        var subtitle: CGSize
        var primaryButton: CGSize
        var secondaryButton: CGSize
    }

    var icon: CGRect
    var title: CGRect
    var subtitle: CGRect
    var primaryButton: CGRect
    var secondaryButton: CGRect

    private typealias Metrics = PicksPanelMetrics

    init(sizes: Sizes, in bounds: CGRect) {
        let buttonsHeight = max(sizes.primaryButton.height, sizes.secondaryButton.height)
        let buttonsWidth = sizes.primaryButton.width + Metrics.accessButtonSpacing + sizes.secondaryButton.width
        let height = sizes.icon.height + Metrics.accessSpacingAfterIcon
            + sizes.title.height + Metrics.accessSpacing
            + sizes.subtitle.height + Metrics.accessSpacingAfterSubtitle
            + buttonsHeight
        let centerX = bounds.midX
        var top = MainPanelMetrics.emptyTextCenterY(in: bounds) + height / 2

        func place(_ size: CGSize, centeredAt x: CGFloat) -> CGRect {
            CGRect(x: (x - size.width / 2).rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
        }

        icon = place(sizes.icon, centeredAt: centerX)
        top -= sizes.icon.height + Metrics.accessSpacingAfterIcon
        title = place(sizes.title, centeredAt: centerX)
        top -= sizes.title.height + Metrics.accessSpacing
        subtitle = place(sizes.subtitle, centeredAt: centerX)
        top -= sizes.subtitle.height + Metrics.accessSpacingAfterSubtitle

        // The buttons are centred on each other vertically, and as a pair horizontally.
        let rowTop = top
        let left = centerX - buttonsWidth / 2
        top = rowTop - (buttonsHeight - sizes.primaryButton.height) / 2
        primaryButton = place(sizes.primaryButton, centeredAt: left + sizes.primaryButton.width / 2)
        top = rowTop - (buttonsHeight - sizes.secondaryButton.height) / 2
        secondaryButton = place(
            sizes.secondaryButton,
            centeredAt: left + sizes.primaryButton.width + Metrics.accessButtonSpacing + sizes.secondaryButton.width / 2
        )
    }
}
