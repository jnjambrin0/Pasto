/// What Escape does while a search is going on, one rung at a time.
nonisolated enum SearchEscape: Equatable {
    /// Where the keyboard focus is when Escape is pressed.
    enum Focus {
        case field
        case strip
    }

    case closeSuggestions
    /// Empty the field; the search stays active and the cleared query can be undone.
    case clearQuery
    /// Leave the search; the panel stays open.
    case dismissSearch
    case closePanel

    /// - Parameter isQueryEmpty: In the field, whether the field's query is empty; over the
    ///   strip, whether the strip shows a list rather than a search.
    static func action(focus: Focus, isSuggestionsMenuOpen: Bool, isQueryEmpty: Bool) -> SearchEscape {
        switch focus {
        case .field:
            if isSuggestionsMenuOpen {
                .closeSuggestions
            } else if isQueryEmpty {
                .dismissSearch
            } else {
                .clearQuery
            }
        case .strip:
            // Over the results there is no intermediate rung: the query goes with the search.
            isQueryEmpty ? .closePanel : .dismissSearch
        }
    }
}
