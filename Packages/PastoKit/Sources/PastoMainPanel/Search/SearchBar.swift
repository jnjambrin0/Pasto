import AppKit
import PastoUI

/// The toolbar's search element: the magnifying glass button at rest, the search field while a
/// search is active. Both occupy the same place and swap by opacity.
final class SearchBar: NSView {
    private static let searchKeyEquivalent = KeyEquivalent("f", modifiers: .command)

    let field = SearchField()

    /// The magnifying glass was clicked, or ⌘F typed while the search is not active. The button
    /// stays in place, invisible, under the active field, so it can still be clicked there.
    var onToggle: (() -> Void)?
    /// ⌘F typed while the search is active.
    var onFilterShortcut: (() -> Void)?

    private(set) var isActive = false

    private let button = ToolbarButton(
        size: ToolbarMetrics.buttonSize,
        symbol: ToolbarMetrics.searchSymbol,
        accessibilityLabel: ToolbarStrings.searchButton
    )

    init() {
        super.init(frame: .zero)
        field.alphaValue = 0
        addSubview(field)
        button.keyEquivalent = Self.searchKeyEquivalent
        button.toolTip = Self.buttonToolTip
        button.onClick = { [weak self] in self?.onToggle?() }
        addSubview(button)
    }

    /// "Search (⌘F)".
    private static var buttonToolTip: String {
        ToolbarStrings.searchToolTip(shortcut: searchKeyEquivalent.displayString)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SearchBar is created in code")
    }

    /// Swaps the button and the field. Called inside the toolbar's animation group, so the two
    /// fade into each other while the toolbar makes room.
    func setActive(_ active: Bool) {
        isActive = active
        button.alphaValue = active ? 0 : 1
        // Under the field the button is out of sight, and so is what it says — to VoiceOver
        // too. It can still be clicked.
        button.toolTip = active ? nil : Self.buttonToolTip
        button.setAccessibilityElement(!active)
        field.alphaValue = active ? 1 : 0
        field.isActive = active
    }

    override func layout() {
        super.layout()
        field.frame = bounds
        button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isActive, Self.searchKeyEquivalent.matches(event) else {
            return super.performKeyEquivalent(with: event)
        }
        onFilterShortcut?()
        return true
    }
}
