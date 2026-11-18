import AppKit
import PastoCore

/// The pasteboard type that says which item a dragged card is: how the places that take a drag
/// of Pasto's items — the panel's strip and tabs, the Paste Stack — recognise one. It belongs to
/// Pasto alone, so it never arrives from another application.
public enum ItemDragType {
    public static let itemID = NSPasteboard.PasteboardType("jnjambrino.Pasto.item-id")

    /// The items a drag carries, in order and without repeats: an item with several pasteboard
    /// items travels as several dragging items with one identifier.
    public static func itemIDs(in pasteboard: NSPasteboard) -> [ItemID] {
        var seen: Set<String> = []
        return (pasteboard.pasteboardItems ?? [])
            .compactMap { $0.string(forType: itemID) }
            .filter { seen.insert($0).inserted }
            .map(ItemID.init)
    }
}

/// Writes one pasteboard item of a dragged item: the content another application would get from
/// a paste, followed by the item's identifier. The data is handed over as it is asked for;
/// nothing is promised for later.
public final class ItemPasteboardWriter: NSObject, NSPasteboardWriting {
    private let itemID: ItemID
    private let content: PasteboardItemSnapshot?

    /// - Parameter content: `nil` for an item with nothing to give other applications; it can
    ///   still be dragged to the places inside Pasto that take items.
    public init(itemID: ItemID, content: PasteboardItemSnapshot?) {
        self.itemID = itemID
        self.content = content
    }

    public func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        let contentTypes = (content?.types ?? []).map { NSPasteboard.PasteboardType($0) }
        return contentTypes + [ItemDragType.itemID]
    }

    public func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == ItemDragType.itemID ? itemID.rawValue : content?.dataByType[type.rawValue]
    }
}
