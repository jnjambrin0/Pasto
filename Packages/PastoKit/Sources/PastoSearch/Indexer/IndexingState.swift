import Foundation
import PastoFoundation

/// How far the indexing of the whole store got, saved after every batch so that a later launch
/// continues instead of starting over.
struct IndexingState: Codable, Equatable, Sendable {
    /// The layout of the index this progress is for. Bump it whenever what is written per item
    /// changes (`SearchIndexItem`, the attribute names): every index out there is then rebuilt.
    ///
    /// 2: everything in Pasto's own attributes, out of the system's search. The rebuild also
    /// deletes what version 1 gave the system with the item's text in `title` and `textContent`.
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var totalItems: Int
    var indexedItems: Int
    /// When the oldest item indexed so far was last used: where a resumed indexing continues from.
    var oldestTimestamp: Date?
    /// Items skipped because they have no usable identifier.
    var invalidItems: Int
}

extension ConfigKey where Value == JSONConfigValue<IndexingState?> {
    static var searchIndexingState: Self {
        ConfigKey("searchIndexingState", default: JSONConfigValue(nil))
    }
}

extension ConfigKey where Value == JSONConfigValue<String?> {
    /// The store the index was built from (`IndexableItemReader.storeIdentifier`).
    static var searchIndexedStoreID: Self {
        ConfigKey("searchIndexedStoreID", default: JSONConfigValue(nil))
    }
}

extension ConfigKey where Value == JSONConfigValue<[String]> {
    /// The identifiers of the image items whose text has not been read yet, in the order they
    /// will be: what lets a launch finish the reading the previous one left half-way.
    static var searchRecognitionQueue: Self {
        ConfigKey("searchRecognitionQueue", default: JSONConfigValue([]))
    }
}

/// What the indexer does when it starts.
enum SearchIndexerStartup: Equatable {
    enum RebuildReason: String, Equatable {
        case noSavedState = "No saved state"
        case storeChanged = "Store identity changed"
        case schemaChanged = "Schema version changed"
    }

    /// Empty the index and index every item.
    case rebuild(RebuildReason)
    /// Continue an indexing that did not finish.
    case resume(IndexingState)
    /// Everything is supposed to be indexed: check that the index still has it.
    case probe(IndexingState)
    case upToDate

    static func plan(
        state: IndexingState?,
        indexedStoreID: String?,
        storeID: String?,
        schemaVersion: Int = IndexingState.currentSchemaVersion
    ) -> SearchIndexerStartup {
        guard let state else { return .rebuild(.noSavedState) }
        if let indexedStoreID, let storeID, indexedStoreID != storeID {
            return .rebuild(.storeChanged)
        }
        if state.schemaVersion != schemaVersion {
            return .rebuild(.schemaChanged)
        }
        if state.indexedItems < state.totalItems {
            return .resume(state)
        }
        return state.totalItems >= 1 ? .probe(state) : .upToDate
    }
}
