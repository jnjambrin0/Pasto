import Foundation

/// What composing needs to know about an item being restored: a value, so that composition does
/// not depend on the store.
struct RestorableItem: Sendable {
    var type: ItemType
    /// Everything the item put on the pasteboard when it was captured.
    var pasteboardItems: [PasteboardItemSnapshot]
    /// Signs what is written (source marker) and names the temporary image copies.
    var sourceApplication: SourceApplication?
    /// When the item was last copied or used — or the moment of the restore, for one that has
    /// left the history —; dates its temporary image copies.
    var timestamp: Date
}

extension RestorableItem {
    /// - Parameter now: Read only for an item that has left the history.
    init(_ item: Item, pasteboardItems: [PasteboardItemSnapshot], now: () -> Date) {
        self.init(
            type: item.type,
            pasteboardItems: pasteboardItems,
            sourceApplication: item.sourceApplication,
            timestamp: item.timestamp ?? now()
        )
    }
}
