import AppKit
import PastoUI

/// Layout values and timings for the search interface.
nonisolated enum SearchMetrics {
    // MARK: Behaviour

    /// Keystrokes closer together than this are undone as one step.
    static let undoCoalescingInterval = Duration.milliseconds(400)
    /// How long the panel stays closed before a search left in it is discarded.
    static let closedPanelResetDelay = Duration.seconds(10)

    // MARK: Toolbar

    /// The active field is as wide as the larger of this and a fraction of the toolbar.
    static let activeMinimumWidth: CGFloat = 400
    static let activeWidthFraction: CGFloat = 0.25

    // MARK: Field

    enum Field {
        /// Black or white at this opacity, behind the field and behind every filter token.
        static let fillOpacity: CGFloat = 0.1
        static let iconLeadingInset: CGFloat = 8
        static let iconToInputSpacing: CGFloat = 4
        static let inputHeight: CGFloat = 20
        static let inputToFiltersSpacing: CGFloat = 4
        static let filtersTrailingInset: CGFloat = 8
        static let filtersButtonWidth: CGFloat = 16

        /// The body text style's size, which every symbol of the field is configured with.
        static let symbolPointSize = NSFont.preferredFont(forTextStyle: .body).pointSize
        static let icon = SymbolDescription("magnifyingglass", pointSize: symbolPointSize)
        static let filtersSymbol = SymbolDescription("line.3.horizontal.decrease", pointSize: symbolPointSize)
        static let clearSymbol = SymbolDescription("xmark.circle.fill", pointSize: symbolPointSize)

        static let clearButtonSide: CGFloat = 16
        static let textToClearSpacing: CGFloat = 4
        static let clearFadeDuration: TimeInterval = 0.12

        /// Vertical inset of the text while the field holds no token; with tokens there is none,
        /// because a token is as tall as the input area.
        static let textVerticalInset: CGFloat = 2
        /// The placeholder starts this far before the text would.
        static let placeholderLeadingOffset: CGFloat = -1

        // The filters button bounces when the filter browser opens and closes.
        static let bounceScales: [CGFloat] = [1, 1.16, 0.98, 1]
        static let bounceKeyTimes: [NSNumber] = [0, 0.35, 0.7, 1]
        static let bounceDuration: TimeInterval = 0.28
    }

    // MARK: Filter icon

    /// A pinboard filter's icon is the pinboard's colour dot at this size wherever it goes: in a
    /// larger place it is centred, not enlarged.
    static let pinboardDotSide: CGFloat = 12

    // MARK: Filter token

    enum Token {
        static let trailingGap: CGFloat = 4
        static let iconSide: CGFloat = 12
        static let iconToLabelSpacing: CGFloat = 2
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 2
        /// The token sits this fraction of its height below the text's baseline.
        static let baselineDropFraction: CGFloat = 0.25
    }

    // MARK: Suggestions menu

    enum Suggestions {
        static let minimumWidth: CGFloat = 120
        /// Kept free between the menu and the bottom of the screen's visible area.
        static let screenBottomMargin: CGFloat = 6
        /// The first row's text starts this far before the word being completed.
        static let textLeadingOffset: CGFloat = 2
        static let cornerRadius: CGFloat = 10

        static let listInset: CGFloat = 5
        static let rowHorizontalPadding: CGFloat = 8
        static let rowVerticalPadding: CGFloat = 3
        /// The place the row's stack gives the icon…
        static let rowIconSlotSide: CGFloat = 18
        /// …and the icon as it shows, centred on that place: 20 × 20, 12 pt from the menu's edge,
        /// in rows that stay 24 pt tall.
        static let rowIconSide: CGFloat = 20
        static let rowSpacing: CGFloat = 7
        static let rowCornerRadius: CGFloat = 7
        static let rowHeight = rowIconSlotSide + 2 * rowVerticalPadding
        /// The part of a selected row's title that was not typed: white at this opacity.
        static let selectedUnmatchedTextOpacity: CGFloat = 0.6

        /// Height of the bands that show there are more rows above or below.
        static let scrollIndicatorHeight: CGFloat = 18
        static let scrollUpSymbol = SymbolDescription("chevron.up", pointSize: 12, weight: .medium)
        static let scrollDownSymbol = SymbolDescription("chevron.down", pointSize: 12, weight: .medium)
        /// One row every this often while the pointer rests on a scroll indicator.
        static let hoverScrollInterval: TimeInterval = 0.075

        /// Page Up and Page Down move the selection by this many rows.
        static let pageStep = 5
        /// After a keyboard move the pointer does not change the selection for this long, so that
        /// rows scrolling under a resting pointer do not steal it.
        static let pointerSelectionCooldown = Duration.milliseconds(100)
    }

    // MARK: Filter browser

    enum Browser {
        /// With the popover's 13 pt on each side, 466 pt wide.
        static let width: CGFloat = 440
        static let minimumHeight: CGFloat = 230
        /// Beyond this the browser scrolls; with the popover it is then 346 pt tall.
        static let maximumHeight: CGFloat = 320
        static let horizontalPadding: CGFloat = 16
        static let sectionBottomPadding: CGFloat = 8
        static let titleVerticalPadding: CGFloat = 10
        static let scrollIndicatorMargin: CGFloat = 10

        static let columnCount = 3
        static let columnSpacing: CGFloat = 6
        static let rowSpacing: CGFloat = 8
        static let minimumColumnWidth: CGFloat = 10

        /// Every filter is a capsule as wide as its column: (440 − 2 × 16 − 2 × 6) / 3 = 132.
        static let itemHeight: CGFloat = 28
        static let itemHorizontalPadding: CGFloat = 10
        static let itemVerticalPadding: CGFloat = 6
        static let itemSpacing: CGFloat = 4
        static let itemIconSide: CGFloat = 16
        static let disclosureSpacing: CGFloat = 8
        static let disclosureIconSide: CGFloat = 12
        /// The same size as the dot in a filter token.
        static let pinboardDotSide: CGFloat = 12

        static let restingFillOpacity: CGFloat = 0.05
        /// Black at this opacity over the resting fill, under the text, while pressed.
        static let pressedFillOpacity: CGFloat = 0.1
        static let keyboardHighlightWidth: CGFloat = 2
        static let keyboardHighlightOutset: CGFloat = 4

        /// A section with this many filters or more starts collapsed…
        static let collapseThreshold = 11
        /// …showing only this many.
        static let collapsedItemLimit = 8
    }
}
