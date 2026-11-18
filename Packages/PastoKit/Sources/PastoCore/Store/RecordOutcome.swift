/// What `WritingContext.record(_:)` did with a captured item.
public struct RecordOutcome: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The content was new: there is one more item.
        case inserted
        /// The content was already in the history: that item went back to its front.
        case movedToFront
        /// The content was stored on a pinboard only: that item entered the history, at its
        /// front, and stays pinned.
        case addedToHistory
    }

    public let id: ItemID
    public let kind: Kind
    /// The history has a different newest item than before. False only when the content was
    /// already the newest item.
    public let didChangeNewestItem: Bool

    public init(id: ItemID, kind: Kind, didChangeNewestItem: Bool) {
        self.id = id
        self.kind = kind
        self.didChangeNewestItem = didChangeNewestItem
    }
}
