import Foundation

/// An item as the search index sees it: what it can be found by, without its pasteboard data.
public struct IndexableItem: Sendable, Hashable, Identifiable {
    /// How much of an item's text the index keeps, in characters.
    public static let maxTextLength = 5000

    public var id: ItemID
    public var type: ItemType
    /// The name the user gave it, if any.
    public var title: String?
    /// The text the item can be found by; `nil` when it has none (always, for an image). As
    /// read from the store, no more than its first `maxTextLength` characters.
    public var text: String?
    public var timestamp: Date
    public var applicationName: String?
    public var deviceName: String?
    /// The pinboard it is on; `nil` for an item that only lives in the history.
    public var pinboardID: ListID?

    public init(
        id: ItemID,
        type: ItemType,
        title: String? = nil,
        text: String? = nil,
        timestamp: Date,
        applicationName: String? = nil,
        deviceName: String? = nil,
        pinboardID: ListID? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.text = text
        self.timestamp = timestamp
        self.applicationName = applicationName
        self.deviceName = deviceName
        self.pinboardID = pinboardID
    }
}
