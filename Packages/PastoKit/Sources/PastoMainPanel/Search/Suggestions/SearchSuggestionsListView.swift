import AppKit
import PastoSearch

/// The rows of the suggestions menu and their selection, which the keyboard and the pointer share.
final class SearchSuggestionsListView: NSView {
    /// The user chose the row at this index.
    var onAccept: ((Int) -> Void)?
    /// Escape was pressed.
    var onEscape: (() -> Void)?

    private var rows: [SearchSuggestionRowView] = []
    private var selection = SuggestionSelection(rowCount: 0)
    /// Running while the pointer may not change the selection, after a keyboard move.
    private var pointerCooldown: Task<Void, Never>?

    /// Rows are stacked from the top.
    override var isFlipped: Bool { true }

    // MARK: - Accessibility

    // A menu whose items are the rows.

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .menu }

    override func accessibilityChildren() -> [Any]? { rows }

    /// Replaces the rows. The new ones start with none selected.
    func setSuggestions(_ suggestions: [SearchSuggestion], icon: (SearchFilter) -> SearchFilterIcon) {
        rows.forEach { $0.removeFromSuperview() }
        rows = suggestions.enumerated().map { index, suggestion in
            let row = SearchSuggestionRowView(suggestion: suggestion, icon: icon(suggestion.filter))
            row.onHover = { [weak self] isInside in self?.pointerDidMove(overRowAt: index, isInside: isInside) }
            row.onPress = { [weak self] in self?.onAccept?(index) }
            addSubview(row)
            return row
        }
        selection = SuggestionSelection(rowCount: rows.count)
        pointerCooldown?.cancel()
        pointerCooldown = nil
        needsLayout = true
    }

    /// The size at which every row shows in full.
    override var fittingSize: NSSize {
        let metrics = SearchMetrics.Suggestions.self
        return NSSize(
            width: (rows.map(\.fittingWidth).max() ?? 0) + 2 * metrics.listInset,
            height: CGFloat(rows.count) * metrics.rowHeight + 2 * metrics.listInset
        )
    }

    /// How far from the list's leading edge the first row's text starts.
    var firstRowTextOffset: CGFloat {
        SearchMetrics.Suggestions.listInset + (rows.first?.textLeadingOffset ?? 0)
    }

    override func layout() {
        super.layout()
        let metrics = SearchMetrics.Suggestions.self
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: metrics.listInset,
                y: metrics.listInset + CGFloat(index) * metrics.rowHeight,
                width: max(bounds.width - 2 * metrics.listInset, 0),
                height: metrics.rowHeight
            )
        }
    }

    // MARK: - Selection

    private func showSelection() {
        for (index, row) in rows.enumerated() {
            row.isSelected = index == selection.index
        }
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
    }

    /// - Returns: Whether the key was the menu's; otherwise it goes on to the search field.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch selection.action(forKeyCode: event.keyCode) {
        case .move(let delta):
            moveSelection(by: delta)
        case .accept:
            if let index = selection.index { onAccept?(index) }
        case .dismiss:
            onEscape?()
        case .passThrough:
            return false
        }
        return true
    }

    private func moveSelection(by delta: Int) {
        selection.move(by: delta)
        showSelection()
        guard let index = selection.index else { return }
        // The selected row and one more on each side stay in view.
        let margin = SearchMetrics.Suggestions.rowHeight
        scrollToVisible(rows[index].frame.insetBy(dx: 0, dy: -margin))

        // Scrolling moves rows under a resting pointer, which must not take the selection.
        pointerCooldown?.cancel()
        pointerCooldown = Task { [weak self] in
            try? await Task.sleep(for: SearchMetrics.Suggestions.pointerSelectionCooldown)
            guard !Task.isCancelled else { return }
            self?.pointerCooldown = nil
        }
    }

    private func pointerDidMove(overRowAt index: Int, isInside: Bool) {
        guard pointerCooldown == nil else { return }
        // Leaving any row clears the selection, even one the keyboard moved elsewhere.
        selection.select(isInside ? index : nil)
        showSelection()
    }
}
