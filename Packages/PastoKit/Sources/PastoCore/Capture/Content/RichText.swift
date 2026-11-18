import AppKit

/// The formatted text an item carries as RTF or RTFD.
///
/// HTML is left alone on purpose: turning it into attributed text needs the main thread and may
/// load remote resources, neither of which capture is allowed to do.
enum RichText {
    /// The item's formatted text, from the first representation that can be read: flat RTFD,
    /// RTFD, RTF.
    static func attributedString(of item: PasteboardItemSnapshot) -> NSAttributedString? {
        for type in [PasteboardType.flatRTFD, PasteboardType.rtfd] {
            if let data = item.dataByType[type], let text = NSAttributedString(rtfd: data, documentAttributes: nil) {
                return text
            }
        }
        return item.dataByType[PasteboardType.rtf].flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
    }

    /// The start of formatted text as RTF, which is what `TextPreview.richTextData` holds: at
    /// most `limit` UTF-16 units, without attachments and without table layout, which a card
    /// cannot draw.
    static func previewData(of text: NSAttributedString, limit: Int) -> Data? {
        let start = NSMutableAttributedString(
            attributedString: text.attributedSubstring(from: NSRange(location: 0, length: min(text.length, limit)))
        )
        let whole = NSRange(location: 0, length: start.length)
        start.enumerateAttribute(.paragraphStyle, in: whole) { value, range, _ in
            guard let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty,
                  let plain = style.mutableCopy() as? NSMutableParagraphStyle
            else { return }
            plain.textBlocks = []
            start.addAttribute(.paragraphStyle, value: plain, range: range)
        }
        return start.rtf(from: whole, documentAttributes: [:])
    }
}
