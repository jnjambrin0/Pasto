import AppKit
import PastoUI

/// Layout values for the toolbar itself. Its height is `MainPanelMetrics.toolbarHeight`.
nonisolated enum ToolbarMetrics {
    /// From the toolbar's edges to the suggestions button and to the "…" button.
    static let edgeInset: CGFloat = 16
    /// Between any two neighbours: suggestions – indicators – search – tabs – "+" – "…".
    static let spacing: CGFloat = 8
    static let buttonSize = ToolbarButton.Size.large
    /// The buttons are circles this wide.
    static let buttonSide = buttonSize.height

    // MARK: Symbols

    /// Every toolbar symbol is drawn at this size, regular weight.
    static let symbolPointSize: CGFloat = 17

    /// Shown until `PicksController` puts the animated icon (`PicksIconView`) in its place.
    static let suggestionsSymbol = SymbolDescription("sparkles", pointSize: symbolPointSize)
    static let searchSymbol = SymbolDescription("magnifyingglass", pointSize: symbolPointSize)
    static let createPinboardSymbol = SymbolDescription("plus", pointSize: symbolPointSize)
    static let moreSymbol = SymbolDescription("ellipsis", pointSize: symbolPointSize)

    // MARK: Pause indicator

    static let pauseSymbol = SymbolDescription("pause.circle", pointSize: symbolPointSize)
    /// The pause menu starts this far above the button's top edge.
    static let pauseMenuTopOverlap: CGFloat = 10
    /// The indicator is this button alone; what the pause is says its tooltip.
    static let pauseButtonSize = ToolbarButton.Size.large

    // MARK: "…" menu

    /// The menu is asked to open this far above the button's top edge.
    static let moreMenuTopOffset: CGFloat = 10
}
