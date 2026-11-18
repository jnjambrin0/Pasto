import PastoCore

/// Where a card is shown, which decides parts of its header.
public nonisolated struct ItemCellContext: Sendable {
    /// The kind of list the strip is showing.
    public enum Collection: Sendable {
        case history
        case pinboard
        case search
        case picks
    }

    public var collection: Collection
    /// The pinboard the item is on, looked up from `Item.listID`; `nil` for an item on none.
    public var pinboard: ClipList?
    /// See `ItemCellModel.quickPasteIndex(forCellAt:)`.
    public var quickPasteIndex: Int?

    public init(collection: Collection, pinboard: ClipList? = nil, quickPasteIndex: Int? = nil) {
        self.collection = collection
        self.pinboard = pinboard
        self.quickPasteIndex = quickPasteIndex
    }
}
