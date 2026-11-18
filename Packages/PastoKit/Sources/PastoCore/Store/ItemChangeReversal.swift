import Foundation

/// What it takes to put the items back as they were before a transaction: the inverse of what
/// the transaction did to them. `StoreWriter.performReversibly` produces one and
/// `WritingContext.apply(_:)` carries it out — which, run reversibly, yields the reversal of
/// the reversal. That pair is all undo and redo are made of.
///
/// It covers where an item is and what it is called: its title, its place in the history, its
/// pinboard and its position there, and its existence. A change of content is not reversed.
public struct ItemChangeReversal: Sendable {
    /// Where an item was and what it was called.
    struct Placement: Sendable, Equatable {
        var title: String?
        var timestamp: Date?
        /// The identifier of its pinboard.
        var pinboard: String?
        var displayOrderInPinboard: Int64
    }

    /// One part of `Placement`, as it was before the transaction changed it.
    enum PlacementValue: Sendable, Equatable {
        case title(String?)
        case timestamp(Date?)
        case pinboard(String?)
        case displayOrderInPinboard(Int64)
    }

    /// Everything needed to create again an item the transaction deleted, under its identifier.
    struct DeletedItem: Sendable {
        var identifier: String
        var checksum: String
        var rawType: Int64
        var rawPreview: Data?
        var rawPasteboardItems: Data
        var createdAt: Date
        var updatedAt: Date?
        var placement: Placement
        var sourceApplicationBundleIdentifier: String?
        var deviceIdentifier: String?
    }

    /// Items to create again.
    var deleted: [DeletedItem] = []
    /// Items to put back where they were, by identifier: only the values the transaction
    /// changed, so that putting them back leaves alone whatever else has happened to the item
    /// since.
    var changed: [String: [PlacementValue]] = [:]
    /// Items the transaction created, to delete.
    var inserted: [String] = []

    /// True when the transaction changed nothing that can be reversed.
    public var isEmpty: Bool {
        deleted.isEmpty && changed.isEmpty && inserted.isEmpty
    }
}
