import Foundation

/// How long the history keeps an item.
///
/// The capacity is an age, not a number of items: after every capture, the items that are on no
/// pinboard and were last copied or used before the cutoff are deleted. Items on a pinboard
/// never expire, and keep their place in the history as well.
enum HistoryRetention {
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60

    /// Items last used before this instant have expired; `nil` when nothing expires.
    static func cutoff(for capacity: HistoryCapacity, at date: Date) -> Date? {
        guard !capacity.isUnlimited else { return nil }
        return date.addingTimeInterval(-TimeInterval(capacity.days) * secondsPerDay)
    }
}
