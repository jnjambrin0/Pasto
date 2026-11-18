import CoreGraphics

/// The frames of the toolbar's elements, placed as Auto Layout constraints with priorities would
/// place them.
///
/// Search, tab bar and "+" travel as one group with fixed gaps. The tab bar is centred in the
/// toolbar when the group fits that way; otherwise the group slides until it meets the leading
/// indicators or the "…" button, and once it touches both the tab bar gives up width and scrolls.
///
/// While a search is active it is the search field that is centred, at its active width; the
/// tab bar — collapsed to icons by then — follows it, and "+" is hidden behind the tab bar's
/// trailing edge.
nonisolated struct ToolbarLayout: Equatable {
    struct Input: Equatable {
        var size: CGSize
        /// The width the tab bar needs to show every tab.
        var tabBarWidth: CGFloat
        var showsSuggestions: Bool
        /// Width of the pause and sync indicators; zero while there are none.
        var indicatorsWidth: CGFloat = 0
        /// A search is active: the field takes the place of the search button.
        var isSearchActive = false
        /// Pixels per point, so that centring never leaves an edge between two pixels.
        var scale: CGFloat
    }

    /// Nil when the suggestions button is not shown.
    let suggestions: CGRect?
    let indicators: CGRect
    let search: CGRect
    let tabBar: CGRect
    let createPinboard: CGRect
    let more: CGRect

    init(_ input: Input) {
        let width = input.size.width
        let height = input.size.height
        let side = ToolbarMetrics.buttonSide
        let spacing = ToolbarMetrics.spacing
        let buttonY = (height - side) / 2

        func button(x: CGFloat, width: CGFloat = side) -> CGRect {
            CGRect(x: x, y: buttonY, width: width, height: side)
        }

        // Fixed ends: suggestions and indicators at the leading edge, "…" at the trailing one.
        // Without suggestions the indicators take their place.
        var leading = ToolbarMetrics.edgeInset
        if input.showsSuggestions {
            suggestions = button(x: leading)
            leading += side + spacing
        } else {
            suggestions = nil
        }
        indicators = CGRect(x: leading, y: 0, width: input.indicatorsWidth, height: height)
        more = button(x: width - ToolbarMetrics.edgeInset - side)

        // The span the group may occupy.
        let lowerLimit = indicators.maxX + spacing
        let upperLimit = more.minX - spacing

        func snapped(_ x: CGFloat) -> CGFloat {
            (x * input.scale).rounded() / input.scale
        }

        if input.isSearchActive {
            let searchWidth = Self.activeSearchWidth(toolbarWidth: width)
            // The leading limit outranks the centring, as it does at rest.
            search = button(x: snapped(max(lowerLimit, (width - searchWidth) / 2)), width: searchWidth)
            let tabBarWidth = max(0, min(input.tabBarWidth, upperLimit - search.maxX - spacing))
            tabBar = CGRect(x: search.maxX + spacing, y: 0, width: tabBarWidth, height: height)
            createPinboard = button(x: tabBar.maxX - side)
            return
        }

        // Width the group needs besides the tab bar; the tab bar yields when the rest does not fit.
        let fixedWidth = side + spacing + spacing + side
        let tabBarWidth = max(0, min(input.tabBarWidth, upperLimit - lowerLimit - fixedWidth))
        let groupWidth = fixedWidth + tabBarWidth

        // Centring the tab bar is the weakest wish, so both limits override it; the leading one
        // wins in the degenerate case where not even an empty tab bar fits.
        let centred = (width - tabBarWidth) / 2 - spacing - side
        let groupX = snapped(max(lowerLimit, min(centred, upperLimit - groupWidth)))

        search = button(x: groupX)
        tabBar = CGRect(x: search.maxX + spacing, y: 0, width: tabBarWidth, height: height)
        createPinboard = button(x: tabBar.maxX + spacing)
    }

    /// How wide the search field is while a search is active.
    static func activeSearchWidth(toolbarWidth: CGFloat) -> CGFloat {
        max(SearchMetrics.activeMinimumWidth, SearchMetrics.activeWidthFraction * toolbarWidth)
    }

    /// Where the "…" menu is asked to put its top-left corner, in the button's coordinates
    /// (origin at the bottom-left corner): at the button's leading edge, above its top. The menu
    /// does not fit there, which is the point: `moreMenuConfinement` then slides it back until
    /// it covers the button.
    static func moreMenuOrigin(buttonBounds: CGRect) -> CGPoint {
        CGPoint(x: buttonBounds.minX, y: buttonBounds.maxY + ToolbarMetrics.moreMenuTopOffset)
    }

    /// The part of the screen the "…" menu may use: the whole height, and as far across as the
    /// button's trailing edge lies in the toolbar. With the panel spanning the screen, that
    /// edge is where the menu's own trailing edge ends up.
    static func moreMenuConfinement(screenFrame: CGRect, moreButtonFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX, y: screenFrame.minY, width: moreButtonFrame.maxX, height: screenFrame.height)
    }
}
