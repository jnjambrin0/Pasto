import AppKit
import PastoCore
import PastoCoreUI

/// What the panel takes from a drag that did not start in it: items dragged from Pasto's own
/// panel, or content dragged from another application.
enum StackDropContent {
    /// The pasteboard types the panel listens for.
    static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        ItemDragType.itemID, .string, .rtf, .html, .URL, .fileURL, .png, .tiff,
    ]

    /// What the panel does with a drag whose source allows `sourceMask`: anyone may give it a
    /// copy; a move — what dragging inside Pasto offers — is only taken for Pasto's own items.
    static func operation(forSourceMask sourceMask: NSDragOperation, carriesItems: Bool) -> NSDragOperation {
        if sourceMask.contains(.copy) {
            .copy
        } else if sourceMask.contains(.move), carriesItems {
            .move
        } else {
            []
        }
    }

    /// Whether the drag carries items of Pasto, by their identifiers.
    static func carriesItems(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [ItemDragType.itemID]) != nil
    }

    /// Everything another application put on the dragging pasteboard, as content to store: every
    /// type of every pasteboard item, with its data. Items without any data are left out, and so
    /// is Pasto's own identifier type, which is no content.
    static func foreignContent(of pasteboard: NSPasteboard) -> [PasteboardItemSnapshot] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            var types: [String] = []
            var dataByType: [String: Data] = [:]
            for type in item.types where type != ItemDragType.itemID {
                guard let data = item.data(forType: type) else { continue }
                types.append(type.rawValue)
                dataByType[type.rawValue] = data
            }
            return types.isEmpty ? nil : PasteboardItemSnapshot(types: types, dataByType: dataByType)
        }
    }
}
