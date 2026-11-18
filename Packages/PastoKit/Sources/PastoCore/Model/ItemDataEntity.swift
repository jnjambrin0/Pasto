import CoreData

/// Every pasteboard representation of an item: the heavy part, only loaded to paste or preview it.
@objc(PastoItemDataEntity)
final class ItemDataEntity: NSManagedObject, ModelEntity {
    static let entityName = "ItemDataEntity"

    @NSManaged var rawPasteboardItems: Data
    @NSManaged var item: ItemEntity?
}

extension ItemDataEntity {
    /// Empty when the blob was written in a format this version cannot read. Large
    /// representations are views into the blob, not copies (`PasteboardItemsBlob`).
    var pasteboardItems: [PasteboardItemSnapshot] {
        PasteboardItemsBlob.decode(rawPasteboardItems) ?? []
    }

    func setPasteboardItems(_ items: [PasteboardItemSnapshot]) throws {
        rawPasteboardItems = try PasteboardItemsBlob.encode(items)
    }
}
