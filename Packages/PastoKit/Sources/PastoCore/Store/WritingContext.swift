import CoreData
import Foundation

/// The operations available inside `StoreWriter.perform`. Only valid there: it works on the
/// writer's context, on the writer's queue.
///
/// Operations that take several identifiers skip the ones that no longer exist (the item may have
/// expired while the user was acting on it); operations on a single item or list throw instead.
public struct WritingContext {
    let context: NSManagedObjectContext
    /// One instant for the whole transaction: stamps `createdAt` and `updatedAt`.
    let now: Date
    let localDeviceIdentifier: String
    /// The most items a mass operation handles in one save.
    let batchSize: Int
    /// Whether a mass operation that outgrows one batch may save what it has done so far and go
    /// on in further transactions. Not inside `performReversibly`: its reversal is read from the
    /// changes still unsaved at the end.
    let savesInBatches: Bool
    /// What the transaction did, for the writer to act on afterwards.
    let tally: WriteTally
}

/// Counts what a transaction did across all its saves.
final class WriteTally {
    /// Items deleted, whether outright or by leaving their last place.
    var deletedItems = 0
}

@available(*, unavailable)
extension WritingContext: Sendable {}

// MARK: - Lookups shared by the operations

extension WritingContext {
    func item(_ id: ItemID) throws -> ItemEntity {
        guard let item = try context.first(ItemEntity.self, where: "identifier", equals: id.rawValue) else {
            throw StoreError.itemNotFound
        }
        return item
    }

    /// The existing items among `ids`, in the order given.
    func items(_ ids: [ItemID]) throws -> [ItemEntity] {
        let request = ItemEntity.makeRequest(NSPredicate(format: "identifier IN %@", ids.map(\.rawValue)))
        let found = try context.fetch(request)
        let byIdentifier = Dictionary(found.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byIdentifier[$0.rawValue] }
    }

    func list(_ id: ListID) throws -> ListEntity {
        guard let list = try context.first(ListEntity.self, where: "identifier", equals: id.rawValue) else {
            throw StoreError.listNotFound
        }
        return list
    }

    func pinboard(_ id: ListID) throws -> ListEntity {
        let list = try list(id)
        guard list.type == .pinboard else {
            throw StoreError.invalidOperation("The clipboard history is not a pinboard")
        }
        return list
    }

    /// The position after the last item of `pinboard`. Computed from the relationship rather than
    /// with a fetch so that it sees what earlier operations of this transaction did.
    func nextDisplayOrder(in pinboard: ListEntity) -> Int64 {
        (pinboard.items.map(\.displayOrderInPinboard).max() ?? -1) + 1
    }

    /// The items of `pinboard` in the order it shows them (`ItemListQuery`, `ItemSortKey`); from
    /// the relationship, for the same reason.
    func orderedItems(of pinboard: ListEntity) -> [ItemEntity] {
        pinboard.items.sorted { first, second in
            let firstKey = ItemSortKey(order: first.displayOrderInPinboard, timestamp: first.timestamp)
            let secondKey = ItemSortKey(order: second.displayOrderInPinboard, timestamp: second.timestamp)
            if firstKey != secondKey {
                return firstKey < secondKey
            }
            return second.identifier.utf8.lexicographicallyPrecedes(first.identifier.utf8)
        }
    }
}
