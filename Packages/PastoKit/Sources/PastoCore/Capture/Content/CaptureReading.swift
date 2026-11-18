import Foundation

/// What was read from the pasteboard, with the first item's string decoded once.
///
/// Type detection, the checksum and the preview all read the first item's string. For a copy of
/// hundreds of megabytes each decoding costs as much memory as the copy itself, so one capture
/// decodes it once and every step reads it from here. Lives for one capture, on one thread.
final class CaptureReading {
    let items: [PasteboardItemSnapshot]

    private var decodedPlainText: String??
    private var decodedURL: URL??

    init(_ items: [PasteboardItemSnapshot]) {
        self.items = items
    }

    var first: PasteboardItemSnapshot? {
        items.first
    }

    /// `first?.plainText`.
    var plainText: String? {
        if let decodedPlainText { return decodedPlainText }
        let plainText = first?.plainText
        decodedPlainText = .some(plainText)
        return plainText
    }

    /// `first?.text`.
    var text: String? {
        first?.text(plainText: plainText)
    }

    /// `first?.url`.
    var url: URL? {
        if let decodedURL { return decodedURL }
        let url = first?.url(plainText: plainText)
        decodedURL = .some(url)
        return url
    }
}
