import Foundation

/// The text an item is indexed by, per type, up to the first `IndexableItem.maxTextLength`
/// characters: all the index keeps of it.
enum IndexableText {
    /// - Parameter characters: How much of the text to keep.
    /// - Returns: `nil` when the item has no text to be found by. An empty text counts as none.
    static func text(
        of items: [PasteboardItemSnapshot],
        preview: ItemPreview,
        type: ItemType,
        characters: Int = IndexableItem.maxTextLength
    ) -> String? {
        let text: String? = switch type {
        case .unknown: joinedStrings(of: items, characters: characters)
        case .text: plainOrFormattedText(of: items, preview: preview, characters: characters)
        case .link: linkText(of: items, preview: preview)
        case .color: colorText(of: items, preview: preview)
        case .files: filesText(of: items, preview: preview)
        // An image is found by the words recognized in it, which the indexer adds later.
        case .image: nil
        }
        return text.flatMap { $0.isEmpty ? nil : String($0.prefix(characters)) }
    }

    /// Every element's string, one after the other with a space between them — as far as the
    /// first `characters` of the whole go. A string longer than that is decoded only so far
    /// (`plainTextPrefix(characters:)`) and ends the text: nothing after it would be kept.
    private static func joinedStrings(of items: [PasteboardItemSnapshot], characters: Int) -> String {
        var strings: [String] = []
        for item in items {
            // Two more than kept: joining with a space can merge one character into another.
            guard let string = item.plainTextPrefix(characters: characters + 2) else { continue }
            strings.append(string.text)
            if !string.isWhole { break }
        }
        return strings.joined(separator: " ")
    }

    private static func plainOrFormattedText(of items: [PasteboardItemSnapshot], preview: ItemPreview, characters: Int) -> String? {
        let joined = joinedStrings(of: items, characters: characters)
        guard joined.isEmpty else { return joined }
        guard let first = items.first else {
            // The pasteboard data is unreadable: the preview is all that is left of the text.
            guard case .text(let textPreview) = preview else { return nil }
            return textPreview.text
        }
        return RichText.attributedString(of: first)?.string ?? first.plainText
    }

    /// The address and, when the preview has it, the title of the page.
    private static func linkText(of items: [PasteboardItemSnapshot], preview: ItemPreview) -> String {
        let linkPreview: LinkPreview? = if case .link(let link) = preview { link } else { nil }
        let url = items.first?.url ?? linkPreview?.url
        return [url?.absoluteString, linkPreview?.title].compactMap(\.self).joined(separator: " ")
    }

    /// The color as it was copied (`rgb(…)` stays `rgb(…)`); `#RRGGBB` only when the data is gone.
    private static func colorText(of items: [PasteboardItemSnapshot], preview: ItemPreview) -> String? {
        if let first = items.first {
            return first.plainText
        }
        guard case .color(let color) = preview else { return nil }
        return String(format: "#%06X", color.colorCode & 0xFFFFFF)
    }

    /// Whole paths, so that the name of a folder finds the files in it.
    private static func filesText(of items: [PasteboardItemSnapshot], preview: ItemPreview) -> String {
        var paths = items.compactMap(\.filePath).filter { !$0.isEmpty }
        if paths.isEmpty, case .files(let files) = preview {
            paths = files.paths.filter { !$0.isEmpty }
        }
        return paths.joined(separator: " ")
    }
}
