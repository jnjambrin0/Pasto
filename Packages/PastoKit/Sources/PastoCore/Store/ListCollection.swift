import CoreData
import os
import PastoFoundation

/// A live view of the user's lists (the clipboard history and the pinboards), in their order.
///
/// Not a fetched results controller, unlike `ItemCollection`: the order of the lists lives in
/// another entity (`ListMetadataEntity.index`), and a controller only tracks objects of the entity
/// it fetches, so it would never notice a reorder. The lists are a handful, so this re-reads them
/// whenever a write that touched a list or its metadata is merged into the view context.
@MainActor
public final class ListCollection {
    public private(set) var snapshot: CollectionSnapshot<ListID>
    /// Called after every change of content with the new snapshot.
    public var onChange: ((CollectionSnapshot<ListID>) -> Void)?

    private let context: NSManagedObjectContext
    /// Ends the observation when the collection goes away.
    private var observation: NotificationCenter.ObservationToken?

    init(context: NSManagedObjectContext) {
        self.context = context
        snapshot = CollectionSnapshot(ids: Self.fetch(in: context).map(\.id))
        // The view context is never written to, so every change reaches it as a merge. Unlike the
        // objects-did-change notification, this one also covers objects nobody has loaded.
        observation = NotificationCenter.default.addObserver(of: context, for: .didMergeChanges) { [weak self] message in
            self?.contextDidMerge(message)
        }
    }

    /// The lists in the user's order.
    static func makeRequest() -> NSFetchRequest<ListEntity> {
        let request = ListEntity.makeRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "metadata.index", ascending: true)]
        request.relationshipKeyPathsForPrefetching = ["metadata"]
        return request
    }

    private func contextDidMerge(_ message: NSManagedObjectContext.DidMergeChangesMessage) {
        let changed = message.insertedIDs.union(message.updatedIDs).union(message.deletedIDs)
        let listEntities = [ListEntity.entityName, ListMetadataEntity.entityName]
        guard changed.contains(where: { listEntities.contains($0.entity.name ?? "") }) else { return }

        let lists = Self.fetch(in: context)
        let ids = lists.map(\.id)
        let updatedIDs = Set(lists.filter { message.updatedIDs.contains($0.objectID) }.map(\.id))
        guard ids != snapshot.ids || !updatedIDs.isEmpty else { return }

        snapshot = CollectionSnapshot(ids: ids, updatedIDs: updatedIDs)
        onChange?(snapshot)
    }

    private static func fetch(in context: NSManagedObjectContext) -> [(id: ListID, objectID: NSManagedObjectID)] {
        do {
            return try context.fetch(makeRequest()).map { (ListID(rawValue: $0.identifier), $0.objectID) }
        } catch {
            Log.logger(.store).error("List collection fetch failed: \(error)")
            return []
        }
    }
}
