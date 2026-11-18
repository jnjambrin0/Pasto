import CoreData
import Foundation

// MARK: - Maintenance

extension WritingContext {
    /// Retention: deletes the items last used before `date`, except the ones on a pinboard,
    /// which stay where they are — in the history too, however old. Returns how many were
    /// deleted.
    ///
    /// Object by object rather than with a batch request: that is what cascades to the
    /// pasteboard data and reaches the view context as ordinary deletions. More than a batch of
    /// them are deleted a batch per save (`forEachBatch`).
    public func deleteHistory(olderThan date: Date) throws -> Int {
        try forEachBatch(of: ItemListQuery.expiring(before: date)) { item in
            context.delete(item)
        }
    }

    /// Empties the history: every item leaves it, and the ones that are on no pinboard are
    /// deleted. Returns how many items left the history. More than a batch of them leave a
    /// batch per save (`forEachBatch`).
    public func eraseHistory() throws -> Int {
        try forEachBatch(of: ItemListQuery.inHistory, body: takeOutOfHistory)
    }

    /// Runs `body` on every item that matches `predicate`, a batch at a time, and returns how
    /// many it ran on. `body` must take each item out of `predicate`.
    ///
    /// Only object IDs are read up front, so the cost of reading is that of the identifiers
    /// however many items there are; each batch then loads its items, with their pasteboard data
    /// for the deletions to cascade to, in two queries. When there is more than one batch and
    /// `savesInBatches` allows it, every batch but the last is saved as a transaction of its own —
    /// what came before in the transaction with the first one — and its objects are turned back
    /// into faults, so memory holds one batch at a time. The last batch is left to the
    /// transaction, as everything is when it all fits in one: the common case, a capture that
    /// lets a few items expire, stays a single transaction.
    private func forEachBatch(of predicate: NSPredicate, body: (ItemEntity) -> Void) throws -> Int {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: ItemEntity.entityName)
        request.predicate = predicate
        request.resultType = .managedObjectIDResultType
        let ids = try context.fetch(request)

        var processed = 0
        for start in stride(from: 0, to: ids.count, by: batchSize) {
            if start > 0, savesInBatches {
                try saveBatch()
            }
            try autoreleasepool {
                let batch = ItemEntity.makeRequest(NSPredicate(format: "self IN %@", Array(ids[start..<min(start + batchSize, ids.count)])))
                batch.relationshipKeyPathsForPrefetching = ["data"]
                for item in try context.fetch(batch) {
                    body(item)
                    processed += 1
                }
            }
        }
        return processed
    }

    /// Saves what the transaction has done so far, and lets go of it.
    func saveBatch() throws {
        tallyPendingDeletions()
        try context.save()
        context.refreshAllObjects()
    }

    /// Adds the items the context is about to delete to the tally: called before each save.
    func tallyPendingDeletions() {
        tally.deletedItems += context.deletedObjects.lazy.filter { $0 is ItemEntity }.count
    }
}
