import CoreData
import os
import PastoFoundation

/// A live, ordered view of the items of one list — the clipboard history (newest first) or a
/// pinboard (in the user's order) — or of the items a search found (newest first).
///
/// It publishes identifiers only; cells ask `StoreReader` for the items they show.
///
/// Made for a year of history. It holds the identifier, object ID and sort key of each member,
/// never a managed object. Every write the view context merges is read back from the store's
/// persistent history, and only the items it touched are looked up again and moved into their
/// place. That work, and the copy of the identifiers each new snapshot needs, happens on a
/// background queue; the main actor only receives the finished snapshot.
@MainActor
public final class ItemCollection {
    public private(set) var snapshot: CollectionSnapshot<ItemID>
    /// Called after every change of content with the new snapshot.
    public var onChange: ((CollectionSnapshot<ItemID>) -> Void)?

    private let follower: ItemCollectionFollower
    /// Ends the observation when the collection goes away.
    private var observation: NotificationCenter.ObservationToken?

    convenience init(list: ListID, viewContext: NSManagedObjectContext, followingContext: NSManagedObjectContext) {
        self.init(
            predicate: ItemListQuery.predicate(for: list),
            sortDescriptors: ItemListQuery.sortDescriptors(for: list),
            ordersByPosition: ItemListQuery.ordersByPosition(list),
            viewContext: viewContext,
            followingContext: followingContext
        )
    }

    /// - Parameters:
    ///   - viewContext: Whose merges tell the collection that the store changed.
    ///   - followingContext: A background context that reads the store for the collection.
    init(
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor],
        ordersByPosition: Bool,
        viewContext: NSManagedObjectContext,
        followingContext: NSManagedObjectContext
    ) {
        follower = ItemCollectionFollower(
            context: followingContext,
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            ordersByPosition: ordersByPosition
        )
        snapshot = CollectionSnapshot(ids: followingContext.performAndWait { [follower] in follower.load() })
        // The index the changes need is built afterwards, while the main thread goes on.
        followingContext.perform { [follower] in follower.prepare() }

        // The view context is never written to, so every write reaches it as a merge, and it
        // posts this after each one — even when it held none of the objects the write touched,
        // which is why what changed is read from the history rather than from the notification.
        observation = NotificationCenter.default.addObserver(of: viewContext, for: .didMergeChanges) { [weak self] _ in
            self?.catchUp()
        }
    }

    /// Returns once every change merged so far has been published: for tests, which need to know
    /// that a write that changed nothing in the collection has been looked at.
    func settle() async {
        await follower.context.perform {}
    }

    private func catchUp() {
        follower.context.perform { [weak self, follower] in
            guard let change = follower.catchUp() else { return }
            // Published in the order the changes were read: the main queue keeps it.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.publish(change)
                }
            }
        }
    }

    private func publish(_ change: ItemCollectionFollower.Change) {
        snapshot = CollectionSnapshot(ids: change.ids, updatedIDs: change.updatedIDs)
        onChange?(snapshot)
    }
}
