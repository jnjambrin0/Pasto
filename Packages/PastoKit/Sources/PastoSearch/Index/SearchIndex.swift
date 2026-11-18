import Foundation
import PastoCore

/// The index items are searched in. Core Spotlight in the app (`SpotlightSearchIndex`).
public protocol SearchIndex: Sendable {
    /// Whether the system can index at all on this Mac.
    var isAvailable: Bool { get }

    /// Adds the items, replacing the ones already indexed under the same identifier.
    ///
    /// - Parameter isUpdate: The items are known to be indexed already.
    func index(_ items: [SearchIndexItem], isUpdate: Bool) async throws
    func delete(_ ids: [ItemID]) async throws
    func deleteAll() async throws

    /// The newest items that match `queryString` (`SearchQueryString`), at most `limit`, newest first.
    func newestItemIDs(matching queryString: String, limit: Int) async throws -> [ItemID]
    /// Whether the index holds anything: how a lost index is told from a healthy one.
    func containsItems() async throws -> Bool
}

public enum SearchIndexError: Error, Equatable, Sendable {
    /// The system's indexing service did not answer; the same call may work in a moment.
    case transientlyUnavailable(code: Int)
}

/// One item as it is written to the index.
public struct SearchIndexItem: Sendable, Hashable {
    /// How much of an item's text is indexed.
    static let maxTextLength = IndexableItem.maxTextLength

    public var id: ItemID
    public var title: String
    public var text: String?
    public var modificationDate: Date
    public var application: String?
    public var type: String
    public var device: String?
    /// The pinboard's identifier; empty for an item that is on none.
    public var pinboard: String

    /// - Parameter recognizedText: The words read in the item's image, which add to its text.
    public init(_ item: IndexableItem, recognizedText: String? = nil) {
        // Each part is cut before they are joined: the result is the start of the whole, without
        // ever copying a text of hundreds of megabytes to keep 5000 characters of it.
        let text = [item.text, recognizedText]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .map { $0.prefix(Self.maxTextLength) }
            .joined(separator: "\n")
        id = item.id
        // An unnamed item is found by what it is.
        title = item.title ?? item.type.searchName
        self.text = text.isEmpty ? nil : String(text.prefix(Self.maxTextLength))
        modificationDate = item.timestamp
        application = item.applicationName
        type = item.type.searchName
        device = item.deviceName
        pinboard = item.pinboardID?.rawValue ?? ""
    }
}
