import PastoUI

/// Which row of the suggestions menu is selected, and how the keyboard moves it. A menu opens
/// with no row selected.
nonisolated struct SuggestionSelection: Equatable {
    /// What a key does while the menu is open.
    enum KeyAction: Equatable {
        case move(by: Int)
        /// Run the selected row.
        case accept
        case dismiss
        /// Not the menu's: the key goes on to the search field.
        case passThrough
    }

    let rowCount: Int
    private(set) var index: Int?

    init(rowCount: Int) {
        self.rowCount = rowCount
    }

    /// Moves the selection `delta` rows down (up when negative) without wrapping around. With
    /// nothing selected it lands on the first row going down and on the last one going up.
    mutating func move(by delta: Int) {
        guard rowCount > 0 else { return }
        guard let index else {
            self.index = delta > 0 ? 0 : rowCount - 1
            return
        }
        self.index = min(max(index + delta, 0), rowCount - 1)
    }

    /// Sets the selection directly, as the pointer does; nil clears it.
    mutating func select(_ index: Int?) {
        self.index = index.flatMap { (0..<rowCount).contains($0) ? $0 : nil }
    }

    /// Modifiers are not looked at. Return, Tab and → accept only when a row is selected;
    /// otherwise they keep their meaning in the field.
    func action(forKeyCode keyCode: UInt16) -> KeyAction {
        switch keyCode {
        case KeyCode.downArrow: .move(by: 1)
        case KeyCode.upArrow: .move(by: -1)
        case KeyCode.pageDown: .move(by: SearchMetrics.Suggestions.pageStep)
        case KeyCode.pageUp: .move(by: -SearchMetrics.Suggestions.pageStep)
        case KeyCode.end: .move(by: rowCount)
        case KeyCode.home: .move(by: -rowCount)
        case KeyCode.returnKey, KeyCode.tab, KeyCode.rightArrow: index == nil ? .passThrough : .accept
        case KeyCode.escape: .dismiss
        default: .passThrough
        }
    }
}
