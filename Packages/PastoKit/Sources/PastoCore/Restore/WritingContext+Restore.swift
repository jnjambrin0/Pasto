import Foundation

extension WritingContext {
    /// What restoring does to the history, and dropping cards on the history's tab too: the items
    /// become the most recent ones, and the history is trimmed to its capacity.
    ///
    /// The items are stamped last to first, each with the clock's reading at that moment, so the
    /// first one ends up the newest. Nothing else changes: an item on a pinboard stays there —
    /// and enters the history if it had left it —, and no item is created.
    ///
    /// - Parameter clock: Read once per item and once for the trim.
    public func moveToFrontOfHistory(_ ids: [ItemID], clock: () -> Date) throws {
        for id in ids.reversed() {
            do {
                try touch(id, at: clock())
            } catch StoreError.itemNotFound {
                // Deleted since it was written to the pasteboard; the others still move.
                continue
            }
        }

        try trimHistory(at: clock())
    }
}
