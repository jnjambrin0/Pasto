import AppKit
import PastoCore
import PastoUI

/// The panel's toolbar: suggestions, status indicators, search, the pinboard tabs, "+" and "…".
/// While a search is active the search field takes the centre, the tabs shrink to their icons
/// and "+" goes away.
///
/// It has no background of its own: it sits on the panel's glass. Its elements are placed by
/// `ToolbarLayout`, which also decides what gives way when space runs out.
public final class Toolbar: LayerBackedView, NSMenuDelegate {
    public let tabBar = TabBar()

    /// The suggestions button was pressed.
    public var onSuggestions: (() -> Void)? {
        get { suggestionsButton.onClick }
        set { suggestionsButton.onClick = newValue }
    }

    /// The "+" button was pressed, or ⇧⌘N typed.
    public var onCreatePinboard: (() -> Void)? {
        get { createPinboardButton.onClick }
        set { createPinboardButton.onClick = newValue }
    }

    /// Builds the menu the "…" button shows. It is the app menu, which also hangs from the menu
    /// bar icon, so the application provides it.
    public var moreMenuProvider: (() -> NSMenu)?

    /// Receives what the user picks in the tabs' context menus.
    /// How many items a list holds, for the entries of the tabs' menus that depend on it.
    public var itemCount: ((ListID) -> Int)? {
        get { tabMenuController.itemCount }
        set {
            tabMenuController.itemCount = newValue
            tabBar.itemCount = newValue
        }
    }

    public weak var tabMenuActions: (any TabMenuActions)? {
        get { tabMenuController.actions }
        set { tabMenuController.actions = newValue }
    }

    /// Whether capture is paused. While it is, the indicators area says so and offers the
    /// pause menu.
    public var pauseStatus: PauseStatus {
        get { pauseIndicator.status }
        set {
            pauseIndicator.status = newValue
            needsLayout = true
        }
    }

    /// Builds the menu the pause indicator's button shows: the app's pause menu.
    public var pauseMenuProvider: (() -> NSMenu)? {
        get { pauseIndicator.menuProvider }
        set { pauseIndicator.menuProvider = newValue }
    }

    /// False where suggestions are not offered: the button goes away and the status indicators
    /// take its place at the leading edge.
    public var showsSuggestionsButton = true {
        didSet {
            suggestionsButton.isHidden = !showsSuggestionsButton
            needsLayout = true
        }
    }

    let suggestionsButton = Toolbar.makeButton(ToolbarMetrics.suggestionsSymbol, ToolbarStrings.suggestionsButton)
    let searchBar = SearchBar()
    let createPinboardButton = Toolbar.makeButton(ToolbarMetrics.createPinboardSymbol, ToolbarStrings.newPinboardButton)
    let moreButton = Toolbar.makeButton(ToolbarMetrics.moreSymbol, ToolbarStrings.moreButton)
    /// The indicators area. Pasto has a single indicator, the pause one: sync is out of scope.
    private let pauseIndicator = PauseIndicatorView(frame: .zero)

    private let tabMenuController = TabMenuController()

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [suggestionsButton, pauseIndicator, searchBar, tabBar, createPinboardButton, moreButton] {
            addSubview(view)
        }

        let createPinboardKey = KeyEquivalent("n", modifiers: [.command, .shift])
        createPinboardButton.keyEquivalent = createPinboardKey
        createPinboardButton.toolTip = ToolbarStrings.createPinboardToolTip(shortcut: createPinboardKey.displayString)
        suggestionsButton.toolTip = ToolbarStrings.suggestionsToolTip
        moreButton.toolTip = ToolbarStrings.moreToolTip

        moreButton.menuProvider = { [weak self] in
            let menu = self?.moreMenuProvider?() ?? NSMenu()
            // The toolbar says where on the screen the menu may go.
            menu.delegate = self
            return menu
        }
        moreButton.menuOrigin = { [weak self] in
            ToolbarLayout.moreMenuOrigin(buttonBounds: self?.moreButton.bounds ?? .zero)
        }

        tabBar.menuProvider = { [weak self] tab in self?.tabMenuController.makeTabMenu(for: tab) }
        tabMenuController.onRename = { [weak self] id in self?.tabBar.beginRenaming(id) }
    }

    private static func makeButton(_ symbol: SymbolDescription, _ label: String) -> ToolbarButton {
        ToolbarButton(size: ToolbarMetrics.buttonSize, symbol: symbol, accessibilityLabel: label)
    }

    // MARK: - Search

    public var isSearchActive: Bool { searchBar.isActive }

    /// Enters or leaves the search arrangement. The elements slide to their new places, and the
    /// magnifying glass and the field fade into each other, with the system's default duration,
    /// easing out.
    func setSearchActive(_ active: Bool, animated: Bool) {
        guard active != isSearchActive else { return }
        let changes = {
            self.searchBar.setActive(active)
            self.tabBar.isCollapsed = active
            self.createPinboardButton.isHidden = active
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
        guard animated, window?.isVisible == true else {
            changes()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            changes()
        }
    }

    override public func layout() {
        super.layout()
        let frames = ToolbarLayout(ToolbarLayout.Input(
            size: bounds.size,
            tabBarWidth: tabBar.intrinsicContentSize.width,
            showsSuggestions: showsSuggestionsButton,
            indicatorsWidth: pauseIndicator.intrinsicContentSize.width,
            isSearchActive: isSearchActive,
            scale: window?.backingScaleFactor ?? 1
        ))
        if let suggestionsFrame = frames.suggestions {
            suggestionsButton.frame = suggestionsFrame
        }
        pauseIndicator.frame = frames.indicators
        searchBar.frame = frames.search
        tabBar.frame = frames.tabBar
        createPinboardButton.frame = frames.createPinboard
        moreButton.frame = frames.more
    }

    // MARK: - "…" menu

    public func confinementRect(for menu: NSMenu, on screen: NSScreen?) -> NSRect {
        // An empty rectangle leaves the placement to the system.
        guard let screen else { return .zero }
        return ToolbarLayout.moreMenuConfinement(screenFrame: screen.frame, moreButtonFrame: moreButton.frame)
    }

    /// The centred frames are snapped to the pixel grid, which depends on the screen.
    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }
}
