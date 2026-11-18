/// One saved transaction of the store, reduced to what it did to items.
public struct HistoryTransaction: Sendable, Equatable {
    public struct ItemChange: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case inserted
            case updated
            case deleted
        }

        public let id: ItemID
        public let kind: Kind

        public init(id: ItemID, kind: Kind) {
            self.id = id
            self.kind = kind
        }
    }

    /// `nil` when the transaction was not written through `StoreWriter` by this version of Pasto.
    public let author: TransactionAuthor?
    public let changes: [ItemChange]

    public init(author: TransactionAuthor?, changes: [ItemChange]) {
        self.author = author
        self.changes = changes
    }
}
