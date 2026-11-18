import Foundation
import PastoCore

/// Keeps the newest of the hits a query streams back, up to a limit. Recency is the only ranking
/// there is.
struct NewestHits: Sendable {
    private struct Hit: Sendable {
        let id: ItemID
        let date: Date

        func isNewer(than other: Hit) -> Bool {
            date != other.date ? date > other.date : id.rawValue > other.id.rawValue
        }
    }

    private let limit: Int
    /// Newest first.
    private var hits: [Hit] = []

    init(limit: Int) {
        self.limit = limit
    }

    /// - Parameter date: When the item was last used; one without a date counts as the oldest.
    mutating func insert(_ id: ItemID, date: Date?) {
        let hit = Hit(id: id, date: date ?? .distantPast)
        // Once the list is full most hits are older than all of it: one comparison tells.
        if hits.count >= limit, let oldest = hits.last, !hit.isNewer(than: oldest) {
            return
        }
        let index = hits.firstIndex { hit.isNewer(than: $0) } ?? hits.endIndex
        guard index < limit else { return }
        hits.insert(hit, at: index)
        if hits.count > limit {
            hits.removeLast()
        }
    }

    var ids: [ItemID] {
        hits.map(\.id)
    }

    /// Whether the list holds as many hits as it keeps: from then on only newer ones get in.
    var isFull: Bool {
        hits.count >= limit
    }
}
