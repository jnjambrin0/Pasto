import Foundation

extension NewItem {
    /// Turns what was read from the pasteboard into an item ready to store: its type, its
    /// checksum and its preview.
    ///
    /// Runs off the caller's actor, whichever it is: building the preview decodes and scales
    /// images. Everything but a files preview happens inside one autorelease pool, so that what a
    /// large copy leaves behind — bridged strings, an archive as large as the content — is gone
    /// before the item goes to the store.
    ///
    /// - Returns: `nil` when there are no items or nothing in them to hash; such content is not stored.
    @concurrent
    public static func captured(from items: [PasteboardItemSnapshot], at timestamp: Date) async -> NewItem? {
        guard !items.isEmpty else { return nil }
        let content = autoreleasepool { () -> (type: ItemType, checksum: String, preview: ItemPreview?)? in
            // Decodes the first item's string once for all three.
            let reading = CaptureReading(items)
            let type = ItemTypeDetector.type(of: reading)
            guard let checksum = ItemChecksum.checksum(of: reading, type: type) else { return nil }
            let preview = type == .files ? nil : ItemPreviewBuilder.immediatePreview(of: reading, type: type)
            return (type, checksum, preview)
        }
        guard let content else { return nil }
        let preview: ItemPreview = if let preview = content.preview {
            preview
        } else {
            await ItemPreviewBuilder.filesPreview(of: items)
        }
        return NewItem(
            type: content.type,
            checksum: content.checksum,
            preview: preview,
            pasteboardItems: items,
            timestamp: timestamp
        )
    }
}
