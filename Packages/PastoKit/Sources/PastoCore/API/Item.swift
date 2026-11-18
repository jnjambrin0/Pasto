import Foundation

/// A clipboard item as the rest of the app sees it: everything but its pasteboard data, which is
/// read on demand with `StoreReader.pasteboardItems(for:)`.
public struct Item: Sendable, Hashable, Identifiable {
    public var id: ItemID
    public var type: ItemType
    /// The name the user gave it, if any.
    public var title: String?
    public var preview: ItemPreview
    /// When it was last copied or used. An item is in the clipboard history while it has one,
    /// and the history is ordered by it; `nil` for an item that only lives on a pinboard.
    public var timestamp: Date?
    public var createdAt: Date
    /// The pinboard it is on, if any. Independent of the history: an item can be in both.
    public var listID: ListID?
    public var displayOrderInPinboard: Int64
    public var sourceApplication: SourceApplication?
    public var device: Device?

    public init(
        id: ItemID,
        type: ItemType,
        title: String? = nil,
        preview: ItemPreview,
        timestamp: Date?,
        createdAt: Date,
        listID: ListID? = nil,
        displayOrderInPinboard: Int64 = 0,
        sourceApplication: SourceApplication? = nil,
        device: Device? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.preview = preview
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.listID = listID
        self.displayOrderInPinboard = displayOrderInPinboard
        self.sourceApplication = sourceApplication
        self.device = device
    }
}
