import Foundation
import PastoFoundation
import PastoSearch

/// Keeps the search field's content and the query in step: reads the query out of every edit,
/// puts filters first, redraws the field when it has to, and runs the field's own undo.
final class SearchInputCoordinator {
    /// The component the cursor is on: what suggestions are offered for.
    struct Candidate: Equatable {
        var query: SearchQuery
        /// Index of the component in `query`.
        var index: Int
        /// The component's place in the field's text.
        var range: NSRange

        var component: SearchQuery.Component { query.components[index] }
    }

    private(set) var query = SearchQuery()

    /// The query changed, by an edit or from outside.
    var onUpdateQuery: ((SearchQuery) -> Void)?
    /// The field has to show this content with this selection.
    var onUpdateView: ((NSAttributedString, NSRange) -> Void)?
    /// The component under the cursor changed; nil withdraws the suggestions.
    var onUpdateSuggestion: ((Candidate?) -> Void)?

    private let render: (SearchQuery) -> NSAttributedString
    private let sleep: @Sendable (Duration) async throws -> Void
    private var history = SearchUndoHistory()
    /// Ends the burst of typing once it has paused for the coalescing interval.
    private var typingPause: Task<Void, Never>?

    /// - Parameters:
    ///   - render: Draws a query as the field's content (`SearchFieldText.attributedString`).
    ///   - sleep: How the coordinator waits out a pause in the typing.
    init(
        render: @escaping (SearchQuery) -> NSAttributedString,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.render = render
        self.sleep = sleep
    }

    // MARK: - Edits

    /// The user is about to turn the field's content into `proposed`, leaving the cursor at
    /// `selection`.
    ///
    /// - Returns: Whether the text view may apply the edit. False when the coordinator has
    ///   redrawn the field instead, because the edit left the query out of order.
    func textShouldChange(to proposed: NSAttributedString, selection: NSRange) -> Bool {
        let written = SearchFieldText.query(in: proposed)
        let normalized = written.normalized(trimmingText: false)
        guard normalized != query else { return true }

        let isInOrder = written == normalized
        let isTyping = normalized.filters.count == query.filters.count
        query = normalized
        let newSelection = isInOrder ? selection : endOfText
        register(SearchFieldState(query: query, selection: newSelection), isTyping: isTyping)

        guard !isInOrder else {
            onUpdateQuery?(query)
            return true
        }
        onUpdateView?(render(query), newSelection)
        onUpdateQuery?(query)
        onUpdateSuggestion?(nil)
        return false
    }

    /// Replaces the query from outside the field: a suggestion was accepted, the filter browser
    /// changed it, or it was typed over the item strip. Nothing happens if it is the query the
    /// field already shows.
    ///
    /// - Parameter updatesSuggestion: Offer suggestions for the new last component; otherwise
    ///   they are withdrawn.
    func setQuery(_ newQuery: SearchQuery, updatesSuggestion: Bool) {
        let normalized = newQuery.normalized(trimmingText: false)
        guard normalized != query else { return }
        query = normalized
        let selection = endOfText
        onUpdateView?(render(query), selection)
        register(SearchFieldState(query: query, selection: selection), isTyping: false)
        onUpdateQuery?(query)
        onUpdateSuggestion?(updatesSuggestion ? candidate(at: selection.location) : nil)
    }

    /// Empties the field.
    ///
    /// - Parameter keepingUndoHistory: Whether the cleared query can be brought back with undo.
    func clear(keepingUndoHistory: Bool) {
        setQuery(SearchQuery(), updatesSuggestion: false)
        if !keepingUndoHistory {
            typingPause?.cancel()
            history.removeAll()
        }
    }

    func selectionDidChange(_ selection: NSRange) {
        onUpdateSuggestion?(candidate(at: selection.location))
    }

    // MARK: - Undo

    /// - Returns: Whether there was something to undo.
    func undo() -> Bool {
        typingPause?.cancel()
        guard let state = history.undo() else { return false }
        show(state)
        return true
    }

    /// - Returns: Whether there was something to redo.
    func redo() -> Bool {
        guard let state = history.redo() else { return false }
        show(state)
        return true
    }

    private func show(_ state: SearchFieldState) {
        query = state.query
        onUpdateView?(render(query), state.selection)
        onUpdateQuery?(query)
        onUpdateSuggestion?(nil)
    }

    private func register(_ state: SearchFieldState, isTyping: Bool) {
        typingPause?.cancel()
        history.register(state, isTyping: isTyping)
        guard isTyping else { return }
        typingPause = Task { [weak self, sleep] in
            do {
                try await sleep(SearchMetrics.undoCoalescingInterval)
            } catch {
                // Another keystroke arrived: the burst goes on.
                return
            }
            await MainActorReturn.ensure()
            guard !Task.isCancelled else { return }
            self?.history.commitPendingTyping()
        }
    }

    // MARK: - Positions

    private var endOfText: NSRange {
        NSRange(location: SearchFieldText.length(of: query), length: 0)
    }

    /// The component that contains `position`, or ends right at it.
    func candidate(at position: Int) -> Candidate? {
        var start = 0
        for (index, component) in query.components.enumerated() {
            let length = SearchFieldText.length(of: component)
            if position <= start + length {
                return Candidate(query: query, index: index, range: NSRange(location: start, length: length))
            }
            start += length
        }
        return nil
    }
}
