import AppKit

/// The one pasteboard item that several restored items become when at least one of them is text
/// or a link.
enum MergedTextElement {
    /// Joins the text of `elements`, in order. Elements without text (an image) are left out;
    /// `nil` when nothing is left.
    ///
    /// With its formatting the result carries RTF and the same text as UTF-16 and UTF-8 plain
    /// text, so that a target that only takes plain text still gets it. When `asPlainText` is set
    /// or the RTF cannot be generated, it carries UTF-8 plain text only. It is signed as Pasto's
    /// write but names no source, since it mixes several.
    static func make(from elements: [PasteboardItemSnapshot], asPlainText: Bool) -> PasteboardItemSnapshot? {
        let merged = NSMutableAttributedString()
        for (index, piece) in elements.compactMap(text(of:)).enumerated() {
            if index > 0 {
                merged.append(NSAttributedString(string: RestoreMetrics.mergeSeparator))
            }
            merged.append(piece)
        }
        guard merged.length > 0 else { return nil }

        let plainText = (RestoreMetrics.plainTextType, Data(merged.string.utf8))
        if !asPlainText, let richText = rtfData(of: merged) {
            return element([
                (RestoreMetrics.rtfType, richText),
                (RestoreMetrics.externalUTF16PlainTextType, externalUTF16(merged.string)),
                plainText,
            ])
        }
        return element([plainText])
    }

    /// The content types in the order given, followed by the own-write marker.
    private static func element(_ content: [(type: String, data: Data)]) -> PasteboardItemSnapshot {
        var dataByType = Dictionary(uniqueKeysWithValues: content.map { ($0.type, $0.data) })
        dataByType[PasteboardMarker.ownWrite] = Data()
        return PasteboardItemSnapshot(types: content.map(\.type) + [PasteboardMarker.ownWrite], dataByType: dataByType)
    }

    // MARK: - Pieces

    /// The element's rich text with its tables undone, or else its plain string.
    private static func text(of element: PasteboardItemSnapshot) -> NSAttributedString? {
        if let richText = richText(of: element) {
            return withoutTextBlocks(richText)
        }
        return element.restorableString.map(NSAttributedString.init(string:))
    }

    private static func richText(of element: PasteboardItemSnapshot) -> NSAttributedString? {
        for type in RestoreMetrics.richTextTypes {
            guard let data = element.dataByType[type] else { continue }
            let text = type == RestoreMetrics.rtfType
                ? NSAttributedString(rtf: data, documentAttributes: nil)
                : NSAttributedString(rtfd: data, documentAttributes: nil)
            if let text {
                return text
            }
        }
        return nil
    }

    /// A copy whose paragraphs belong to no text block. The cells of a table cannot survive being
    /// joined with other text, so they become ordinary paragraphs.
    private static func withoutTextBlocks(_ text: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        copy.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            style.textBlocks = []
            copy.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return copy
    }

    // MARK: - Output

    /// UTF-16 in its external form: with a byte-order mark, as `public.utf16-external-plain-text` asks.
    static func externalUTF16(_ string: String) -> Data {
        var data = Data([0xFF, 0xFE])
        for unit in string.utf16 {
            data.append(UInt8(truncatingIfNeeded: unit))
            data.append(UInt8(truncatingIfNeeded: unit >> 8))
        }
        return data
    }

    private static func rtfData(of text: NSAttributedString) -> Data? {
        try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
        )
    }
}
