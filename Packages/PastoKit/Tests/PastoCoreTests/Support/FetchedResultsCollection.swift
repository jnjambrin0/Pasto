import CoreData
@testable import PastoCore
import PastoFoundation

/// A simpler item collection: a fetched results controller over every member, read again after
/// each change. Kept as the reference the current `ItemCollection` must agree with.
@MainActor
final class FetchedResultsCollection {
    private(set) var snapshot: CollectionSnapshot<ItemID>
    var onChange: ((CollectionSnapshot<ItemID>) -> Void)?

    private let controller: NSFetchedResultsController<ItemEntity>
    private let relay = Relay()

    init(predicate: NSPredicate, sortDescriptors: [NSSortDescriptor], context: NSManagedObjectContext) {
        let request = ItemEntity.makeRequest(predicate)
        request.sortDescriptors = sortDescriptors
        request.propertiesToFetch = ["identifier", "timestamp", "displayOrderInPinboard"]
        controller = NSFetchedResultsController(fetchRequest: request, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
        try? controller.performFetch()
        snapshot = CollectionSnapshot(ids: (controller.fetchedObjects ?? []).map { ItemID(rawValue: $0.identifier) })
        relay.onContentChange = { [weak self] updated in
            guard let self else { return }
            snapshot = CollectionSnapshot(
                ids: (controller.fetchedObjects ?? []).map { ItemID(rawValue: $0.identifier) },
                updatedIDs: Set(updated.map(ItemID.init))
            )
            onChange?(snapshot)
        }
        controller.delegate = relay
    }

    isolated deinit {
        controller.delegate = nil
    }

    private final class Relay: NSObject, NSFetchedResultsControllerDelegate {
        var onContentChange: ((Set<String>) -> Void)?
        private var updated: Set<String> = []

        func controller(
            _ controller: NSFetchedResultsController<any NSFetchRequestResult>,
            didChange anObject: Any,
            at indexPath: IndexPath?,
            for type: NSFetchedResultsChangeType,
            newIndexPath: IndexPath?
        ) {
            guard type == .update || type == .move, let item = anObject as? ItemEntity else { return }
            updated.insert(item.identifier)
        }

        func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
            let changed = updated
            updated = []
            onContentChange?(changed)
        }
    }
}
