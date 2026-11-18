import Foundation

/// What capture produces and the store consumes: an item ready to be saved.
public struct NewItem: Sendable {
    public var type: ItemType
    /// Deduplication key: recording an item whose checksum is already stored moves that one to the front.
    public var checksum: String
    public var preview: ItemPreview
    public var pasteboardItems: [PasteboardItemSnapshot]
    public var title: String?
    public var sourceApplication: SourceApplication?
    public var timestamp: Date

    public init(
        type: ItemType,
        checksum: String,
        preview: ItemPreview,
        pasteboardItems: [PasteboardItemSnapshot],
        title: String? = nil,
        sourceApplication: SourceApplication? = nil,
        timestamp: Date
    ) {
        self.type = type
        self.checksum = checksum
        self.preview = preview
        self.pasteboardItems = pasteboardItems
        self.title = title
        self.sourceApplication = sourceApplication
        self.timestamp = timestamp
    }
}
