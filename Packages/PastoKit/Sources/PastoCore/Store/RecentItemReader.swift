import CoreData
import Foundation

/// Read access to the store for suggestions, off the main actor: the newest items of the
/// clipboard history, where each came from, and the text the suggestion rules classify.
public final class RecentItemReader: Sendable {
    /// A history item as suggestions see it: never its content.
    public struct RecentItem: Sendable, Hashable {
        public var id: ItemID
        public var type: ItemType
        public var sourceAppBundleIdentifier: String?
    }

    /// Holds no objects between reads: every read resets it.
    private let context: NSManagedObjectContext

    public init(stack: PersistentStack) {
        context = stack.container.newBackgroundContext()
    }

    /// The newest `limit` items of the clipboard history, newest first.
    public func newestHistoryItems(limit: Int) async throws -> [RecentItem] {
        try await context.perform { [context] in
            defer { context.reset() }
            let request = ItemEntity.makeRequest(ItemListQuery.inHistory)
            request.sortDescriptors = ItemListQuery.sortDescriptors(for: .clipboard)
            request.fetchLimit = limit
            request.relationshipKeyPathsForPrefetching = ["sourceApplication"]
            return try context.fetch(request).map(RecentItem.init)
        }
    }

    /// The item, or `nil` if it no longer exists.
    public func item(_ id: ItemID) async throws -> RecentItem? {
        try await context.perform { [context] in
            defer { context.reset() }
            return try context.first(ItemEntity.self, where: "identifier", equals: id.rawValue).map(RecentItem.init)
        }
    }

    /// The string of a text or link item, as the suggestion rules read it: the first pasteboard
    /// item's plain text, or its address as stored, whichever representation comes first; empty
    /// when it has none. `nil` for any other item and for one that no longer exists.
    public func classifiableText(of id: ItemID) async throws -> String? {
        try await context.perform { [context] in
            defer { context.reset() }
            guard let item = try context.first(ItemEntity.self, where: "identifier", equals: id.rawValue),
                  item.type == .text || item.type == .link
            else { return nil }
            // Only now is the item's data unarchived: an image's can weigh megabytes.
            return item.data?.pasteboardItems.first?.plainText ?? ""
        }
    }
}

extension RecentItemReader.RecentItem {
    init(_ entity: ItemEntity) {
        self.init(
            id: ItemID(rawValue: entity.identifier),
            type: entity.type,
            sourceAppBundleIdentifier: entity.sourceApplication?.bundleIdentifier
        )
    }
}
