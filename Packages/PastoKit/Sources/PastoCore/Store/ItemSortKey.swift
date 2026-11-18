import Foundation

/// Where an item goes in a collection, as `ItemListQuery` orders them: by position on a pinboard
/// (`displayOrderInPinboard`, ascending), then newest first (`timestamp`, descending, an item
/// without one last). Two items with the same key go by identifier, descending.
struct ItemSortKey: Comparable, Sendable {
    /// `displayOrderInPinboard`; 0 for the orders that only look at the date.
    var order: Int64
    /// `timestamp` in seconds since the reference date; `-infinity` without one.
    var time: Double

    init(order: Int64 = 0, timestamp: Date?) {
        self.init(order: order, time: timestamp?.timeIntervalSinceReferenceDate ?? -.infinity)
    }

    init(order: Int64, time: Double) {
        self.order = order
        self.time = time
    }

    /// Whether `lhs` comes first.
    static func < (lhs: ItemSortKey, rhs: ItemSortKey) -> Bool {
        lhs.order != rhs.order ? lhs.order < rhs.order : lhs.time > rhs.time
    }
}
