import AppKit
import PastoCore
import PastoCoreUI
import UniformTypeIdentifiers

/// What an editor writes when the user saves: the pasteboard representations that replace
/// everything the item held. Always a single pasteboard item; the store then detects the type
/// again and rebuilds the checksum and the preview from it.
nonisolated enum ItemContentComposer {
    /// An edited image, already encoded.
    enum EncodedImage {
        case png(Data)
        case jpeg(Data)
    }

    private static let plainText = UTType.utf8PlainText.identifier
    private static let richText = UTType.rtf.identifier
    private static let url = UTType.url.identifier
    private static let urlName = "public.url-name"

    /// Text from the editor: the plain characters, preceded by RTF when the text has formatting
    /// the editor keeps.
    static func text(_ text: NSAttributedString) -> [PasteboardItemSnapshot] {
        let normalized = EditableText.normalized(text)
        var representations = [(plainText, Data(normalized.string.utf8))]
        if EditableText.hasFormatting(normalized),
           let rtf = normalized.rtf(from: NSRange(location: 0, length: normalized.length), documentAttributes: [:]) {
            representations.insert((richText, rtf), at: 0)
        }
        return [snapshot(representations)]
    }

    /// An edited link: its address as text and as a URL, and the title the page had, which is
    /// how the title survives the rebuilding of the preview.
    static func link(_ link: URL, title: String) -> [PasteboardItemSnapshot] {
        let address = Data(link.absoluteString.utf8)
        return [snapshot([(plainText, address), (url, address), (urlName, Data(title.utf8))])]
    }

    static func image(_ image: EncodedImage) -> [PasteboardItemSnapshot] {
        switch image {
        case .png(let data): [snapshot([(UTType.png.identifier, data)])]
        case .jpeg(let data): [snapshot([(UTType.jpeg.identifier, data)])]
        }
    }

    /// A colour is stored as the text of its hexadecimal value, which type detection reads
    /// back as a colour.
    static func color(_ color: ColorCode) -> [PasteboardItemSnapshot] {
        [snapshot([(plainText, Data(color.hexString.utf8))])]
    }

    /// The content of a New Text Item: a link when the text is one address and nothing else,
    /// text otherwise.
    static func newTextItem(_ text: NSAttributedString) -> [PasteboardItemSnapshot] {
        guard let link = wholeLink(in: text.string) else { return self.text(text) }
        let address = Data(link.absoluteString.utf8)
        return [snapshot([(plainText, address), (url, address)])]
    }

    /// The address `string` consists of once trimmed, if it is exactly one. A mail address is
    /// text, not a link.
    static func wholeLink(in string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let whole = NSRange(location: 0, length: (trimmed as NSString).length)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: trimmed, options: [], range: whole),
              match.range == whole,
              let link = match.url, link.scheme?.lowercased() != "mailto"
        else { return nil }
        return link
    }

    private static func snapshot(_ representations: [(String, Data)]) -> PasteboardItemSnapshot {
        PasteboardItemSnapshot(
            types: representations.map(\.0),
            dataByType: Dictionary(representations, uniquingKeysWith: { first, _ in first })
        )
    }
}
