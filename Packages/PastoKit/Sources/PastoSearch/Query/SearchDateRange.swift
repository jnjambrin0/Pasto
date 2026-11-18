import Foundation

/// The dates a `date` filter lets through: from `start` up to, not including, `end`.
public struct SearchDateRange: Sendable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// Reads the value of a `date` filter: exactly two numbers, in seconds since 1970.
    public init?(filterValue: String) {
        let bounds = filterValue.split(separator: " ").map { Double($0) }
        guard bounds.count == 2, let start = bounds[0], let end = bounds[1] else { return nil }
        self.init(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }

    /// How the range is written in a filter: whole seconds
    /// since 1970, widened outwards so that the range never loses a fraction of a second.
    public var filterValue: String {
        let start = Int(start.timeIntervalSince1970.rounded(.down))
        let end = Int(end.timeIntervalSince1970.rounded(.up))
        return "\(start) \(end)"
    }

    public var filter: SearchFilter {
        SearchFilter(type: .date, value: filterValue)
    }
}

/// The date ranges offered by name, in the order they are listed.
public enum SearchDatePreset: Sendable, Hashable, CaseIterable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case last30Days

    /// Fixed, not localized, like the names of the item types.
    public var name: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        case .last30Days: "Last 30 days"
        }
    }

    /// The preset's range as of `now`. It is computed again every time it is asked for, so a
    /// filter made from "Today" yesterday is no longer today's.
    ///
    /// - Returns: `nil` if the calendar cannot do the arithmetic, which no real calendar fails at.
    public func range(now: Date, calendar: Calendar) -> SearchDateRange? {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date? {
            calendar.date(byAdding: .day, value: offset, to: today)
        }
        // The first day of the week, whichever the user's calendar says that is.
        let thisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))

        let bounds: (start: Date?, end: Date?) = switch self {
        case .today: (today, day(1))
        case .yesterday: (day(-1), today)
        case .thisWeek: (thisWeek, thisWeek.flatMap { calendar.date(byAdding: .day, value: 7, to: $0) })
        case .lastWeek: (thisWeek.flatMap { calendar.date(byAdding: .weekOfYear, value: -1, to: $0) }, thisWeek)
        case .last30Days: (day(-30), day(1))
        }
        guard let start = bounds.start, let end = bounds.end else { return nil }
        return SearchDateRange(start: start, end: end)
    }
}
