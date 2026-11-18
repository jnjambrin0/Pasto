/// Classifies what was copied.
enum ItemTypeDetector {
    /// The first of these types present among all the items decides the base type. Hence
    /// anything with a file URL is "files" — even a single image file — and formatted text that
    /// also carries an image is text.
    private static let priority: [(pasteboardType: String, itemType: ItemType)] = [
        (PasteboardType.fileURL, .files),
        (PasteboardType.rtf, .text),
        (PasteboardType.png, .image),
        (PasteboardType.jpeg, .image),
        (PasteboardType.heic, .image),
        (PasteboardType.tiff, .image),
        (PasteboardType.icns, .image),
        (PasteboardType.url, .link),
        (PasteboardType.utf8PlainText, .text),
        (PasteboardType.plainText, .text),
        (PasteboardType.text, .text),
    ]

    static func type(of items: [PasteboardItemSnapshot]) -> ItemType {
        type(of: CaptureReading(items))
    }

    static func type(of reading: CaptureReading) -> ItemType {
        let present = Set(reading.items.flatMap(\.types))
        guard let base = priority.first(where: { present.contains($0.pasteboardType) })?.itemType else {
            return .unknown
        }
        switch base {
        case .text:
            return refinedTextType(of: reading)
        case .link:
            return confirmedLinkType(of: reading)
        default:
            return base
        }
    }

    /// Text is looked at again, through the first item only: it may be a colour or a link.
    private static func refinedTextType(of reading: CaptureReading) -> ItemType {
        guard reading.first != nil else { return .text }
        // The colour test comes after the address test but wins over it.
        let hasAddress = reading.url != nil
        if let string = reading.plainText, HexColor.code(of: string) != nil {
            return .color
        }
        return hasAddress ? confirmedLinkType(of: reading) : .text
    }

    /// A candidate link stays one only if it is a link and nothing more.
    private static func confirmedLinkType(of reading: CaptureReading) -> ItemType {
        LinkDetector.isWholeLink(reading.plainText) ? .link : .text
    }
}
