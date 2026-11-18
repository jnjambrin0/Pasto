import AppKit
import PastoUI

/// Sizes, insets and timings for the main panel: its window, layout and item strip.
nonisolated enum MainPanelMetrics {
    // MARK: Window

    static let defaultHeight: CGFloat = 332
    static let minimumHeight: CGFloat = 252
    static let maximumHeight: CGFloat = 412

    /// The panel slides its content up from below the screen edge; the window frame never animates.
    static let showDuration: TimeInterval = 0.15
    static let showTimingControlPoints: (Float, Float, Float, Float) = (0.2, 0.8, 0.2, 1.0)
    /// Hiding uses the system ease-in-ease-out curve.
    static let hideDuration: TimeInterval = 0.2
    /// With "Reduce motion" the content does not slide: it fades in and out in place, this long.
    static let reducedMotionFadeDuration: TimeInterval = 0.15

    static let frameAutosaveName = "PastoMainWindow"

    /// Height of the draggable strip along the panel's top edge.
    static let resizeHandleHeight: CGFloat = 10

    /// A card dragged out of the panel closes it this long after the pointer crosses the
    /// panel's edge, even if the pointer then stays still.
    static let dragExitCloseDelay = Duration.milliseconds(130)

    // MARK: Layout

    /// The glass backdrop reaches the window's top edge and stops short of the other three.
    static let backgroundInset: CGFloat = 8
    static let backgroundCornerRadius: CGFloat = 26
    static let toolbarHeight: CGFloat = 60

    // MARK: Item strip

    static let stripTopInset: CGFloat = 8
    static let stripBottomInset: CGFloat = 24
    static let stripSideInset: CGFloat = 24
    static let stripInteritemSpacing: CGFloat = 24

    // MARK: Text in place of cards

    // One style for every line the strip shows without cards — an empty history or pinboard,
    // "Searching…", "Nothing found", no suggestions — and for the suggestions' access block.

    /// System font, regular, at this size.
    static let emptyTextFontSize: CGFloat = 26
    /// Black or white, by appearance, at this opacity.
    static let emptyTextOpacity: CGFloat = 0.26
    static var emptyTextFont: NSFont { .systemFont(ofSize: emptyTextFontSize) }
    /// With Increase Contrast on, the system's secondary label colour instead, which is much
    /// stronger.
    static var emptyTextColor: NSColor {
        NSColor(name: nil) { appearance in
            if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                return .secondaryLabelColor
            }
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(emptyTextOpacity)
        }
    }

    /// The offset of the text's centre from the strip's, with the y axis pointing down: the text
    /// sits 17 pt above the middle.
    static let emptyTextVerticalOffset: CGFloat = -17

    /// Where the centre of the text goes, in a non-flipped view as large as the strip.
    static func emptyTextCenterY(in bounds: CGRect) -> CGFloat {
        bounds.midY - emptyTextVerticalOffset
    }

    /// `leadingContentWidth` is the width taken by notice cards before the first item.
    static func stripConfiguration(leadingContentWidth: CGFloat = 0) -> CollectionContentLayout.Configuration {
        CollectionContentLayout.Configuration(
            top: stripTopInset,
            left: leadingContentWidth + stripSideInset,
            bottom: stripBottomInset,
            right: stripSideInset,
            interitemSpacing: stripInteritemSpacing
        )
    }
}
