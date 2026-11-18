import Foundation

/// What a link leads to, by the response's `Content-Type`, as far as its preview cares.
enum LinkContentKind: Equatable {
    /// A web page, read for its title, icon and image.
    case page
    /// An image the system can decode, shown as the link's image.
    case image
    /// A PDF, shown by its first page as Link Presentation does (`LinkDocumentThumbnail`).
    case document
    /// Anything else — a text file, a video, an SVG — described by its name and the system's
    /// icon for its kind; it is not downloaded.
    case file
    /// No `Content-Type`: a page if it looks like one.
    case undeclared

    init(mimeType: String?) {
        guard let mimeType else {
            self = .undeclared
            return
        }
        switch mimeType {
        case "text/html", "application/xhtml+xml":
            self = .page
        case "application/pdf", "application/x-pdf":
            self = .document
        case "image/svg+xml":
            self = .file
        case let type where type.hasPrefix("image/"):
            self = .image
        default:
            self = .file
        }
    }

    /// Whether a response without a `Content-Type` starts like an HTML document, by the patterns
    /// browsers sniff for (WHATWG MIME Sniffing, "HTML").
    static func looksLikeHTML(_ data: Data) -> Bool {
        var bytes = data.prefix(512)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        let text = String(decoding: bytes.drop { [0x09, 0x0A, 0x0C, 0x0D, 0x20].contains($0) }, as: UTF8.self).lowercased()
        if text.hasPrefix("<!--") { return true }
        let tags = ["<!doctype html", "<html", "<head", "<script", "<iframe", "<h1", "<div", "<font", "<table",
                    "<a", "<style", "<title", "<b", "<body", "<br", "<p", "<meta", "<link"]
        return tags.contains { tag in
            guard text.hasPrefix(tag) else { return false }
            let next = text.dropFirst(tag.count).first
            return next == " " || next == ">" || next == "\t" || next == "\n" || next == "\r"
        }
    }
}
