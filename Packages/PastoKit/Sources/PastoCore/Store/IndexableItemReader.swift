import CoreData
import Foundation

/// Read access to the store for the search indexer, off the main actor: it goes through every
/// item and loads pasteboard data, neither of which the view context should be made to do.
public final class IndexableItemReader: Sendable {
    private let coordinator: NSPersistentStoreCoordinator
    /// Holds no objects between reads: every read resets it.
    private let context: NSManagedObjectContext

    public init(stack: PersistentStack) {
        coordinator = stack.container.persistentStoreCoordinator
        context = stack.container.newBackgroundContext()
    }

    /// Identifies the store file: it changes when the store is replaced by another one.
    public var storeIdentifier: String? {
        coordinator.persistentStores.first?.identifier
    }

    /// The identifiers of every item, newest first; with a date, only of those older than it.
    ///
    /// An item's age is its `IndexableItem.timestamp`: its last use or, for one that lives on a
    /// pinboard only, its creation. Every item has one, so the oldest item of what has been
    /// indexed marks exactly where to go on from.
    public func itemIDs(before date: Date? = nil) async throws -> [ItemID] {
        try await context.perform { [context] in
            let request = NSFetchRequest<NSDictionary>(entityName: ItemEntity.entityName)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["identifier", "timestamp", "createdAt"]
            // The age is not a stored property: filtered and sorted here.
            let aged = try context.fetch(request).compactMap { row -> (id: ItemID, age: Date)? in
                guard let identifier = row["identifier"] as? String, let createdAt = row["createdAt"] as? Date else { return nil }
                return (ItemID(rawValue: identifier), row["timestamp"] as? Date ?? createdAt)
            }
            return aged
                .filter { item in date.map { item.age < $0 } ?? true }
                .sorted { $0.age > $1.age }
                .map(\.id)
        }
    }

    /// The existing items among `ids`, newest first.
    ///
    /// One item's pasteboard data is in memory at a time, and only until its text is read: a
    /// batch of large copies is never held at once.
    public func items(_ ids: [ItemID]) async throws -> [IndexableItem] {
        try await context.perform { [context] in
            defer { context.reset() }
            let request = ItemEntity.makeRequest(NSPredicate(format: "identifier IN %@", ids.map(\.rawValue)))
            request.relationshipKeyPathsForPrefetching = ["list", "sourceApplication", "device"]
            return try context.fetch(request)
                .map { entity in
                    autoreleasepool {
                        let item = IndexableItem(entity)
                        // The data object would otherwise keep its blob until the batch is over.
                        if let data = entity.data, !data.isFault {
                            context.refresh(data, mergeChanges: false)
                        }
                        return item
                    }
                }
                .sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// The item's image as it was copied (the first one it has), or `nil` if it has none or no
    /// longer exists.
    public func imageData(for id: ItemID) async throws -> Data? {
        try await context.perform { [context] in
            defer { context.reset() }
            let item = try context.first(ItemEntity.self, where: "identifier", equals: id.rawValue)
            return autoreleasepool { item?.data?.pasteboardItems.lazy.compactMap(\.imageData).first }
        }
    }
}

extension IndexableItem {
    init(_ entity: ItemEntity) {
        let type = entity.type
        self.init(
            id: ItemID(rawValue: entity.identifier),
            type: type,
            title: entity.title,
            // Not read for an image: its pasteboard data is the image itself. For the rest, only
            // what the index keeps is decoded.
            text: type == .image ? nil : IndexableText.text(
                of: entity.data?.pasteboardItems ?? [], preview: entity.preview, type: type
            ),
            timestamp: entity.timestamp ?? entity.createdAt,
            applicationName: entity.sourceApplication?.name,
            deviceName: entity.device?.name,
            pinboardID: entity.list.flatMap { $0.type == .pinboard ? ListID(rawValue: $0.identifier) : nil }
        )
    }
}
