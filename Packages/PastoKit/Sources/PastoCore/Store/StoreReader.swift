import CoreData
import os
import PastoFoundation

/// Read access to the store for the UI, on the view context. Returns values, never managed objects.
@MainActor
public final class StoreReader {
    private let context: NSManagedObjectContext
    private let container: NSPersistentContainer
    private nonisolated let storeURL: URL?
    private let log = Log.logger(.store)

    public init(stack: PersistentStack) {
        container = stack.container
        context = stack.container.viewContext
        storeURL = stack.container.persistentStoreCoordinator.persistentStores.first?.url
    }

    /// Where an item collection reads the store, off the main thread: a context of its own, whose
    /// queue keeps that collection's changes in order without making it wait for another's.
    private func followingContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    // MARK: - Items

    public func item(_ id: ItemID) -> Item? {
        items([id]).first
    }

    /// The existing items among `ids`, in the order given.
    public func items(_ ids: [ItemID]) -> [Item] {
        let request = ItemEntity.makeRequest(NSPredicate(format: "identifier IN %@", ids.map(\.rawValue)))
        request.relationshipKeyPathsForPrefetching = ["list", "sourceApplication", "device"]
        let byIdentifier = Dictionary(fetch(request).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byIdentifier[$0.rawValue].map(Item.init) }
    }

    /// Everything the item put on the pasteboard, or `nil` if the item no longer exists.
    ///
    /// Large representations are views into the stored blob, not copies.
    public func pasteboardItems(for id: ItemID) -> [PasteboardItemSnapshot]? {
        let request = ItemEntity.makeRequest(NSPredicate(format: "identifier == %@", id.rawValue))
        request.fetchLimit = 1
        return fetch(request).first?.data?.pasteboardItems
    }

    /// The existing items among `ids`, newest first: how search results are shown.
    public func itemIDs(among ids: [ItemID]) -> [ItemID] {
        let request = ItemEntity.makeRequest(NSPredicate(format: "identifier IN %@", ids.map(\.rawValue)))
        request.sortDescriptors = ItemListQuery.sortDescriptors(for: .clipboard)
        request.propertiesToFetch = ["identifier", "timestamp"]
        return fetch(request).map { ItemID(rawValue: $0.identifier) }
    }

    /// A live view of the existing items among `ids`, newest first: search results, which follow
    /// the store — one deleted leaves, one used again moves to the front, one changed is
    /// reported as updated.
    public func itemCollection(among ids: [ItemID]) -> ItemCollection {
        ItemCollection(
            predicate: NSPredicate(format: "identifier IN %@", ids.map(\.rawValue)),
            sortDescriptors: ItemListQuery.sortDescriptors(for: .clipboard),
            ordersByPosition: false,
            viewContext: context,
            followingContext: followingContext()
        )
    }

    public func itemCount(in list: ListID) -> Int {
        count(ItemListQuery.predicate(for: list))
    }

    /// A live view of the items `list` shows.
    public func itemCollection(for list: ListID) -> ItemCollection {
        ItemCollection(list: list, viewContext: context, followingContext: followingContext())
    }

    // MARK: - Lists

    /// The clipboard history and the pinboards, in the user's order.
    public func lists() -> [ClipList] {
        fetch(ListCollection.makeRequest()).map(ClipList.init)
    }

    public func list(_ id: ListID) -> ClipList? {
        let request = ListEntity.makeRequest(NSPredicate(format: "identifier == %@", id.rawValue))
        request.fetchLimit = 1
        return fetch(request).first.map(ClipList.init)
    }

    /// A live view of the user's lists.
    public func listCollection() -> ListCollection {
        ListCollection(context: context)
    }

    // MARK: - History capacity and storage

    /// How long the history keeps items ("Keep History").
    public var historyCapacity: HistoryCapacity {
        guard case .clipboard(let capacity) = list(.clipboard)?.attributes else { return .month }
        return capacity
    }

    /// How many history items `capacity` would delete if it applied at `date`.
    public func expiredHistoryItemCount(for capacity: HistoryCapacity, at date: Date = Date()) -> Int {
        guard let cutoff = HistoryRetention.cutoff(for: capacity, at: date) else { return 0 }
        return count(ItemListQuery.expiring(before: cutoff))
    }

    /// Every item in the store: the history and the pinboards.
    public func totalItemCount() -> Int {
        count(nil)
    }

    /// The bytes the store takes on disk: the space allocated to the database, its write-ahead
    /// log and the item data Core Data keeps in files next to it (`totalFileAllocatedSize`). Walks
    /// a directory, hence off the main actor.
    @concurrent
    public nonisolated func storeSize() async -> Int64 {
        guard let storeURL else { return 0 }
        let fileManager = FileManager.default
        let name = storeURL.lastPathComponent
        let directory = storeURL.deletingLastPathComponent()
        let supportDirectory = directory.appending(
            path: ".\(storeURL.deletingPathExtension().lastPathComponent)_SUPPORT", directoryHint: .isDirectory
        )

        var files = [name, "\(name)-wal", "\(name)-shm"].map { directory.appending(path: $0, directoryHint: .notDirectory) }
        if let enumerator = fileManager.enumerator(at: supportDirectory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            while let file = enumerator.nextObject() as? URL {
                files.append(file)
            }
        }
        return files.reduce(0) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
    }

    // MARK: - Sources

    /// The names of the applications some item was copied from, in ascending order.
    public func sourceApplicationNames() -> [String] {
        names(of: .application) ?? names(of: ApplicationEntity.self)
    }

    /// The names of the devices some item was copied on, in ascending order.
    public func deviceNames() -> [String] {
        names(of: .device) ?? names(of: DeviceEntity.self)
    }

    /// Read by looking one item up per name (`SourceNamesQuery`); `nil` for a store in memory.
    private func names(of source: SourceNamesQuery.Source) -> [String]? {
        guard let storeURL, storeURL.path != "/dev/null" else { return nil }
        return SourceNamesQuery.names(of: source, inStoreAt: storeURL)
    }

    /// The application called `name` that items were copied from, with its icon: what a search
    /// filter, which only knows the name, is drawn with. Of several with one name, the first by
    /// bundle identifier.
    public func sourceApplication(named name: String) -> SourceApplication? {
        first(ApplicationEntity.self, named: name, orderedBy: "bundleIdentifier").map(SourceApplication.init)
    }

    /// The device called `name` that items were copied on. Of several with one name, the first
    /// by identifier.
    public func device(named name: String) -> Device? {
        first(DeviceEntity.self, named: name, orderedBy: "identifier").map(Device.init)
    }

    private func first<Entity: ModelEntity>(_ entity: Entity.Type, named name: String, orderedBy key: String) -> Entity? {
        let request = entity.makeRequest(NSPredicate(format: "name == %@", name))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: true)]
        request.fetchLimit = 1
        return fetch(request).first
    }

    /// The distinct `name`s of the rows of `entity` that have items, as Core Data reads them:
    /// counting every item of each row. For a store in memory, which SQLite cannot be asked
    /// directly, and should the direct question fail.
    private func names<Entity: ModelEntity>(of entity: Entity.Type) -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: entity.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["name"]
        request.returnsDistinctResults = true
        request.predicate = NSPredicate(format: "items.@count > 0")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        do {
            return try context.fetch(request).compactMap { $0["name"] as? String }
        } catch {
            log.error("Fetch failed: \(error)")
            return []
        }
    }

    // MARK: - Changes

    /// Emits after the store changes, whoever wrote: for those who hold item values and have to
    /// check them again. It says nothing about what changed, and several changes in a row may
    /// arrive as one.
    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        // Posted once the view context has merged a save, so a read made on hearing it is current.
        // The token only ever goes back to `NotificationCenter`, which is thread-safe.
        nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: nil
        ) { _ in continuation.yield() }
        continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        return stream
    }

    // MARK: -

    private func count(_ predicate: NSPredicate?) -> Int {
        do {
            return try context.count(for: ItemEntity.makeRequest(predicate))
        } catch {
            log.error("Count failed: \(error)")
            return 0
        }
    }

    /// A failed fetch means the store is unreadable; the UI is better served by "nothing" than by
    /// an error on every read, so it is logged and reads as empty.
    private func fetch<Entity: ModelEntity>(_ request: NSFetchRequest<Entity>) -> [Entity] {
        do {
            return try context.fetch(request)
        } catch {
            log.error("Fetch failed: \(error)")
            return []
        }
    }
}
