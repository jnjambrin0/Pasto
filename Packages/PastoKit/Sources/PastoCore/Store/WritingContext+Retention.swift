import Foundation

extension WritingContext {
    /// Applies the history's capacity as of `date`: deletes the expired items that are on no
    /// pinboard and returns how many they were; a pinned item is exempt altogether. Runs at the
    /// end of everything that adds to or reorders the history: captures and restores.
    @discardableResult
    func trimHistory(at date: Date) throws -> Int {
        guard case .clipboard(let capacity) = try list(.clipboard).attributes,
              let cutoff = HistoryRetention.cutoff(for: capacity, at: date)
        else { return 0 }
        return try deleteHistory(olderThan: cutoff)
    }

    /// "Keep History": stores the new capacity and applies it at once, so that lowering the limit
    /// deletes what the user was just told would be deleted. Returns how many items expired.
    @discardableResult
    public func setHistoryCapacity(_ capacity: HistoryCapacity) throws -> Int {
        let history = try list(.clipboard)
        try history.setAttributes(.clipboard(capacity: capacity))
        history.updatedAt = now
        return try trimHistory(at: now)
    }
}
