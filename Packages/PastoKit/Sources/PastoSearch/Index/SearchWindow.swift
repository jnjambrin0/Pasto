import Foundation

/// How far back a search asks.
///
/// Core Spotlight hands over every match of a query, in no order, and only the newest hundred are
/// kept: one letter or a common word in a year of heavy use is hundreds of thousands of matches
/// for each keystroke. So a search first asks about the last
/// day, and reaches further back only while it has found fewer than a hundred. Each window takes
/// in everything newer than its start, the future included, so once one holds a hundred matches,
/// nothing outside it can be newer than them: its newest hundred are the ones a query over all
/// of time gives. The last window has no start.
///
/// Measured with 300 000 items (Tools/CaptureBench): a window only has a start, because a range
/// with both ends costs Spotlight ~45 ms more per query; and there is no window of a year,
/// because a bound that takes in nearly every item costs more (54 ms for a rare word) than
/// asking about all of time (4 ms).
struct SearchWindow: Equatable, Sendable {
    /// How far back from now each window reaches, before the last one, which reaches back to
    /// the beginning.
    static let reaches: [TimeInterval] = [1, 7, 30].map { $0 * 24 * 3600 }

    /// Inclusive; `nil` for the last window, which has no beginning.
    var start: Date?

    /// Every window, smallest first: the last day, week and month, and all of time.
    static func sequence(endingAt now: Date) -> [SearchWindow] {
        // Whole seconds: the bound is written with second precision.
        reaches.map { SearchWindow(start: Date(timeIntervalSince1970: (now.timeIntervalSince1970 - $0).rounded(.down))) }
            + [SearchWindow(start: nil)]
    }

    /// `queryString` limited to this window, by the date the index keeps for every item.
    func restricting(_ queryString: String) -> String {
        guard let start else { return queryString }
        return "(\(queryString)) && \(SearchIndexAttribute.modificationDate) >= $time.iso(\(start.formatted(.iso8601)))"
    }

    func contains(_ date: Date) -> Bool {
        start.map { date >= $0 } ?? true
    }
}
