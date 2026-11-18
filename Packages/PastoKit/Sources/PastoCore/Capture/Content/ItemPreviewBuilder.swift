import Foundation

/// Builds what a cell draws for an item, so that showing the history never loads pasteboard data.
enum ItemPreviewBuilder {
    /// The stored text of a preview is cut at this many UTF-16 units.
    static let textLimit = 500

    static func preview(of items: [PasteboardItemSnapshot], type: ItemType) async -> ItemPreview {
        let reading = CaptureReading(items)
        guard type == .files else { return immediatePreview(of: reading, type: type) }
        return await filesPreview(of: items)
    }

    /// The preview of every type but files, which waits for Quick Look: built without suspending,
    /// so that capture can build it inside an autorelease pool.
    static func immediatePreview(of reading: CaptureReading, type: ItemType) -> ItemPreview {
        switch type {
        case .text:
            return textPreview(of: reading)
        case .link:
            // A link whose address cannot be rebuilt has no preview.
            guard let item = reading.first, let url = reading.url else { return .unknown }
            // The page's title, icon and image arrive later, once fetched; until then the
            // name the copying application gave the link stands in for the title.
            return .link(LinkPreview(url: url, title: item.urlName))
        case .image:
            // The first image stands for the item.
            return reading.items.lazy.compactMap(\.imageData).first.flatMap(ImageThumbnail.preview).map(ItemPreview.image) ?? .unknown
        case .color:
            return reading.plainText.flatMap(HexColor.code).map { .color(ColorPreview(colorCode: $0)) } ?? .unknown
        case .files, .unknown:
            return .unknown
        }
    }

    static func filesPreview(of items: [PasteboardItemSnapshot]) async -> ItemPreview {
        let paths = items.compactMap(\.filePath)
        // Size and picture describe the first file only.
        return .files(FilesPreview(
            paths: paths,
            totalByteCount: paths.first.map(FileSummary.byteCount),
            thumbnailData: await paths.first.asyncFlatMap(FileSummary.thumbnailData)
        ))
    }

    /// The start of the text, exactly as copied, with the full length alongside. An item that
    /// carries formatted text is previewed and measured by it (an attachment counts as one unit),
    /// with the RTF to render its start; any other, by its string.
    private static func textPreview(of reading: CaptureReading) -> ItemPreview {
        guard let item = reading.first else { return .unknown }
        if let formatted = RichText.attributedString(of: item) {
            return .text(TextPreview(
                text: truncated(formatted.string),
                characterCount: formatted.length,
                richTextData: RichText.previewData(of: formatted, limit: textLimit)
            ))
        }
        guard let text = reading.text else { return .unknown }
        let length = utf16Count(of: text)
        return .text(TextPreview(text: truncated(text, utf16Count: length), characterCount: length))
    }

    /// At most `textLimit` UTF-16 units, never splitting a character: a cut at the unit itself
    /// could leave half a character behind.
    static func truncated(_ text: String) -> String {
        truncated(text, utf16Count: utf16Count(of: text))
    }

    /// The characters from the start whose UTF-16 units add up to `textLimit` at most. Walked
    /// from the start rather than found by offset, which would index the whole string.
    private static func truncated(_ text: String, utf16Count: Int) -> String {
        guard utf16Count > textLimit else { return text }
        var end = text.startIndex
        var units = 0
        while end < text.endIndex {
            let next = text.index(after: end)
            units += text.utf16.distance(from: end, to: next)
            guard units <= textLimit else { break }
            end = next
        }
        return String(text[..<end])
    }

    /// `text.utf16.count`, counted on the string's UTF-8 bytes — one unit per scalar, two for
    /// those of four bytes. Asking the string itself builds an index of all its UTF-16 offsets
    /// first: a sixth of the size of a text that is not ASCII, and a third of a second for one
    /// of 300 MB.
    static func utf16Count(of text: String) -> Int {
        let counted = text.utf8.withContiguousStorageIfAvailable { bytes in
            var count = 0
            for byte in bytes {
                // Every byte but a continuation starts a scalar; a 4-byte one takes a surrogate pair.
                count += (byte & 0xC0 != 0x80 ? 1 : 0) + (byte >= 0xF0 ? 1 : 0)
            }
            return count
        }
        return counted ?? text.utf16.count
    }
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
