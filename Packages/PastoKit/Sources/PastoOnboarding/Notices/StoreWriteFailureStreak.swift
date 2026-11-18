/// Counts the writes to the store that failed in a row, to decide when a card says that what is
/// copied is not being saved. One failure can be a passing hiccup; from the third in a row the
/// card goes up, and the first write that is saved again takes it away.
nonisolated struct StoreWriteFailureStreak {
    static let threshold = 3

    private var count = 0

    /// Whether the card should be on show after a failed write.
    mutating func writeDidFail() -> Bool {
        count += 1
        return count >= Self.threshold
    }

    /// A write was saved: the streak is over and no card is owed.
    mutating func writeDidSucceed() {
        count = 0
    }
}
