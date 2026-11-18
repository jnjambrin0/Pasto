import Foundation

// How capture reads an item: as text, as a link, as an image, as a file.

extension PasteboardItemSnapshot {
    /// The characters a typed string keeps when it is tried as a web address: those of a query,
    /// those of a fragment, and `#`. Everything else is percent-encoded first.
    private static let urlCharacters = CharacterSet.urlQueryAllowed
        .union(.urlFragmentAllowed)
        .union(CharacterSet(charactersIn: "#"))

    private static let imageTypes = [
        PasteboardType.png,
        PasteboardType.jpeg,
        PasteboardType.heic,
        PasteboardType.tiff,
        PasteboardType.icns,
    ]

    /// The text the item stands for: its string or, when that is empty, the text of its
    /// formatted content. `nil` when there is no string at all or nothing but emptiness: such an
    /// item has nothing to hash and is not captured.
    var text: String? {
        text(plainText: plainText)
    }

    /// `text`, given the item's `plainText` already decoded (`CaptureReading`).
    func text(plainText: String?) -> String? {
        guard let string = plainText else { return nil }
        if !string.isEmpty {
            return string
        }
        guard let formatted = RichText.attributedString(of: self)?.string, !formatted.isEmpty else { return nil }
        return formatted
    }

    /// The address the item points to: its `public.url` data, or else its string once
    /// percent-encoded. Any scheme counts, but there
    /// must be a scheme and a host — which is what keeps ordinary text from being an address.
    var url: URL? {
        url(plainText: plainText)
    }

    /// `url`, given the item's `plainText` already decoded (`CaptureReading`).
    func url(plainText: String?) -> URL? {
        let candidate = dataByType[PasteboardType.url].flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            ?? plainText.flatMap(Self.typedURL)
        guard let candidate, candidate.scheme != nil, let host = candidate.host(), !host.isEmpty else { return nil }
        return candidate
    }

    /// A typed string as an address: percent-encoded first, so that what a person would type in
    /// an address bar counts.
    static func typedURL(_ string: String) -> URL? {
        guard TypedAddress.mayHaveSchemeAndHost(string) else { return nil }
        return string.addingPercentEncoding(withAllowedCharacters: urlCharacters).flatMap { URL(string: $0) }
    }

    /// The name the copying application gave a link (browsers put the page title here),
    /// trimmed; `nil` when there is none.
    var urlName: String? {
        guard let data = dataByType[PasteboardType.urlName], let name = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The item's image: the first representation it has among PNG, JPEG, HEIC, TIFF and ICNS.
    public var imageData: Data? {
        Self.imageTypes.lazy.compactMap { dataByType[$0] }.first
    }

    /// The path of the file the item refers to. `NSURL` resolves the file-reference addresses
    /// Finder puts on the pasteboard (`file:///.file/id=…`) into real paths.
    public var filePath: String? {
        dataByType[PasteboardType.fileURL]
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { NSURL(string: $0)?.path }
    }
}
