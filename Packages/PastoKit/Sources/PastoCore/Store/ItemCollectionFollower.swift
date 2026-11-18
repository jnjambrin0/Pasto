import CoreData
import os
import PastoFoundation

/// The part of `ItemCollection` that reads the store and keeps the members in order. Lives on its
/// context's queue: every call but the initializer goes through `context.perform`.
final class ItemCollectionFollower: @unchecked Sendable {
    /// A new content to publish.
    struct Change: Sendable {
        var ids: [ItemID]
        var updatedIDs: Set<ItemID>
    }

    let context: NSManagedObjectContext
    private let predicate: NSPredicate
    private let sortDescriptors: [NSSortDescriptor]
    /// Whether the order starts with the position on a pinboard.
    private let ordersByPosition: Bool
    private var members = OrderedItemList<NSManagedObjectID>([])
    /// How far into the persistent history `members` goes.
    private var historyToken: NSPersistentHistoryToken?
    /// The identifiers last published, held here as well so that the last reference to an array
    /// of a few hundred thousand strings is let go on this queue, not on the main thread.
    private var published: [[ItemID]] = []
    private let log = Log.logger(.store)

    init(context: NSManagedObjectContext, predicate: NSPredicate, sortDescriptors: [NSSortDescriptor], ordersByPosition: Bool) {
        self.context = context
        self.predicate = predicate
        self.sortDescriptors = sortDescriptors
        self.ordersByPosition = ordersByPosition
    }

    /// Reads the whole list and returns its identifiers.
    func load() -> [ItemID] {
        // Taken before reading: a write saved in between is then both read and replayed, which
        // changes nothing, instead of being missed.
        historyToken = context.persistentStoreCoordinator?.currentPersistentHistoryToken(fromStores: nil)
        members = OrderedItemList(fetchMembers(among: nil))
        return keep(members.ids)
    }

    /// Indexes the members for the changes to come; done right after `load()`, but not while
    /// the main thread waits for it.
    func prepare() {
        members.prepare()
    }

    /// What changed in the list since the last call, or `nil` when nothing did.
    func catchUp() -> Change? {
        let changes: ItemChanges?
        do {
            changes = try readHistory()
        } catch {
            // The history after the collection's position is gone (purged, or another store).
            log.error("Item collection lost its place in the history, reading the list again: \(error)")
            return reload()
        }
        guard let changes else { return nil }
        return apply(changes)
    }

    /// Hands out `ids`, keeping the last two arrays handed out: the one shown and the one the
    /// main thread compared it with.
    private func keep(_ ids: [ItemID]) -> [ItemID] {
        published.append(ids)
        if published.count > 2 {
            published.removeFirst()
        }
        return ids
    }

    // MARK: - Following the store

    /// What a run of transactions did to items.
    private struct ItemChanges {
        /// Inserted or updated, and not deleted afterwards: to look up again.
        var touched: Set<NSManagedObjectID> = []
        /// Updated: reported as updated if they are members before and after.
        var updated: Set<NSManagedObjectID> = []
        var deleted: Set<NSManagedObjectID> = []
    }

    /// The item changes saved since the last call; `nil` when nothing at all was saved.
    private func readHistory() throws -> ItemChanges? {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: historyToken)
        request.resultType = .transactionsAndChanges
        let result = try context.execute(request) as? NSPersistentHistoryResult
        guard let transactions = result?.result as? [NSPersistentHistoryTransaction], let last = transactions.last else {
            return nil
        }
        historyToken = last.token

        var changes = ItemChanges()
        for transaction in transactions {
            for change in transaction.changes ?? [] where change.changedObjectID.entity.name == ItemEntity.entityName {
                let object = change.changedObjectID
                switch change.changeType {
                case .insert:
                    changes.touched.insert(object)
                case .update:
                    changes.touched.insert(object)
                    changes.updated.insert(object)
                case .delete:
                    // Object IDs are never reused: a deletion is final.
                    changes.touched.remove(object)
                    changes.deleted.insert(object)
                @unknown default:
                    changes.touched.insert(object)
                }
            }
        }
        return changes
    }

    private func apply(_ changes: ItemChanges) -> Change? {
        guard !changes.touched.isEmpty || !changes.deleted.isEmpty else { return nil }
        members.prepare()
        let updatedMembers = changes.updated.filter(members.contains)
        let found = changes.touched.isEmpty ? [] : fetchMembers(among: changes.touched)

        let removed = members.remove(changes.deleted.union(changes.touched))
        members.insert(found)
        // An item that was a member and still is was updated, wherever it went.
        let updatedIDs = Set(found.lazy.filter { updatedMembers.contains($0.handle) }.map(\.id))
        guard removed || !found.isEmpty else { return nil }
        return Change(ids: keep(members.ids), updatedIDs: updatedIDs)
    }

    /// Reads the whole list again: for when the history cannot say what changed. Every item that
    /// stays is reported as updated, since any of them may have.
    private func reload() -> Change {
        let previous = Set(members.ids)
        let ids = load()
        return Change(ids: ids, updatedIDs: previous.intersection(ids))
    }

    // MARK: - Reading the store

    /// A member is read as its object ID, identifier and sort key, and nothing else; this is
    /// the first of them.
    private static func objectIDProperty() -> NSExpressionDescription {
        let property = NSExpressionDescription()
        property.name = "objectID"
        property.expression = NSExpression.expressionForEvaluatedObject()
        property.expressionResultType = .objectIDAttributeType
        return property
    }

    /// Fetches in parts of this many objects at most, to keep each query's list of keys short.
    private static let lookupBatchSize = 1_000

    /// The members of the collection — or, with `handles`, the members among those objects — as
    /// the store has them now. Sorted when they are all of them.
    private func fetchMembers(among handles: Set<NSManagedObjectID>?) -> [OrderedItemList<NSManagedObjectID>.Member] {
        guard let handles else {
            return fetchMembers(matching: predicate, sorted: true)
        }
        let all = Array(handles)
        return stride(from: 0, to: all.count, by: Self.lookupBatchSize).flatMap { start in
            let batch = all[start..<min(start + Self.lookupBatchSize, all.count)]
            return fetchMembers(
                matching: NSCompoundPredicate(andPredicateWithSubpredicates: [NSPredicate(format: "self IN %@", Array(batch)), predicate]),
                sorted: false
            )
        }
    }

    private func fetchMembers(matching predicate: NSPredicate, sorted: Bool) -> [OrderedItemList<NSManagedObjectID>.Member] {
        let request = NSFetchRequest<NSDictionary>(entityName: ItemEntity.entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        request.propertiesToFetch = [Self.objectIDProperty(), "identifier", "timestamp"]
            + (ordersByPosition ? ["displayOrderInPinboard"] : [])
        if sorted {
            request.sortDescriptors = sortDescriptors
        }
        return autoreleasepool {
            let rows: [NSDictionary]
            do {
                rows = try context.fetch(request)
            } catch {
                log.error("Item collection fetch failed: \(error)")
                return []
            }
            // Keys made once, and values read as the Objective-C objects they are, of the
            // classes the model guarantees: subscripting with Swift strings and casting to Swift
            // types took longer than the fetch itself.
            let objectIDKey: NSString = "objectID"
            let identifierKey: NSString = "identifier"
            let timestampKey: NSString = "timestamp"
            let orderKey: NSString = "displayOrderInPinboard"
            var result: [OrderedItemList<NSManagedObjectID>.Member] = []
            result.reserveCapacity(rows.count)
            for row in rows {
                guard let handle = row.object(forKey: objectIDKey), let identifier = row.object(forKey: identifierKey) else { continue }
                let order = ordersByPosition ? row.object(forKey: orderKey).map { unsafeDowncast($0 as AnyObject, to: NSNumber.self).int64Value } ?? 0 : 0
                let time = row.object(forKey: timestampKey).map { unsafeDowncast($0 as AnyObject, to: NSDate.self).timeIntervalSinceReferenceDate }
                result.append(.init(
                    handle: unsafeDowncast(handle as AnyObject, to: NSManagedObjectID.self),
                    id: ItemID(rawValue: unsafeDowncast(identifier as AnyObject, to: NSString.self) as String),
                    key: ItemSortKey(order: order, time: time ?? -.infinity)
                ))
            }
            return result
        }
    }
}
