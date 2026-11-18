/// A filter offered to the user: for the word under the cursor, or in the filter browser.
public struct SearchSuggestion: Sendable, Hashable {
    public var filter: SearchFilter
    /// What the user reads. Not always the filter's value: a pinboard is offered by its name and
    /// filtered by its identifier, a date by the name of its preset.
    public var title: String
    /// The parts of `title` that match what was typed, to highlight them. Empty in the browser.
    public var matchedRanges: [Range<String.Index>]

    public init(filter: SearchFilter, title: String, matchedRanges: [Range<String.Index>] = []) {
        self.filter = filter
        self.title = title
        self.matchedRanges = matchedRanges
    }
}
