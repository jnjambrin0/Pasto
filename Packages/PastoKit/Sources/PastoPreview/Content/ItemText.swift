import AppKit
import PastoCore

/// The text of a text item as the preview shows it.
nonisolated enum ItemText {
    /// The whole text of the item's first pasteboard item: formatted if it carries RTF or RTFD,
    /// else its string, else nothing. Further pasteboard items are not shown.
    static func text(of item: PasteboardItemSnapshot?) -> NSAttributedString {
        if let formatted = item?.formattedText {
            return withoutTableLayout(formatted)
        }
        return NSAttributedString(string: item?.plainText ?? "")
    }

    /// Table cells cannot be laid out by the editor; their text is kept as ordinary paragraphs.
    private static func withoutTableLayout(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty,
                  let plain = style.mutableCopy() as? NSMutableParagraphStyle
            else { return }
            plain.textBlocks = []
            result.addAttribute(.paragraphStyle, value: plain, range: range)
        }
        return result
    }
}
