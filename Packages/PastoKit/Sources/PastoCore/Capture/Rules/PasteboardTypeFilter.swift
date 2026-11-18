/// Which representations of a change are fetched. A type that is filtered out is never requested
/// from its owner.
struct PasteboardTypeFilter: Sendable {
    /// All that is read of content that arrived through Universal Clipboard.
    private static let remoteClipboardTypes: Set<String> = [
        PasteboardType.utf8PlainText,
        PasteboardType.text,
        PasteboardType.rtf,
    ]

    /// Compared with the frontmost bundle identifier in lowercase.
    private static let excelBundleIdentifier = "com.microsoft.excel"

    /// All that is read of what Excel copies: a cell range as text, not as a picture of it.
    private static let excelTypes: Set<String> = [
        PasteboardType.utf16PlainText,
        PasteboardType.utf8PlainText,
    ]

    /// Office's live-link types, compared exactly: they point back into the source document
    /// and mean nothing once pasted elsewhere. `com.microsoft.DataObject` is kept, since it
    /// carries the copied content itself.
    private static let officeLinkTypes: Set<String> = [
        "com.microsoft.ObjectLink",
        "com.microsoft.Link-Source",
    ]

    private let isRemoteClipboard: Bool
    private let isFromExcel: Bool
    /// An image that comes with the URL of its file is kept as an image: without the URL it is
    /// not classified as a file.
    private let dropsFileURL: Bool

    /// - Parameter types: The types of every item on the pasteboard.
    init(types: [String], frontmostBundleIdentifier: String?) {
        isRemoteClipboard = types.contains(PasteboardType.remoteClipboard)
        isFromExcel = frontmostBundleIdentifier?.lowercased() == Self.excelBundleIdentifier
        dropsFileURL = types.contains(PasteboardType.fileURL) && types.contains(PasteboardType.png)
    }

    func shouldRead(_ type: String) -> Bool {
        if isRemoteClipboard, !Self.remoteClipboardTypes.contains(type) {
            return false
        }
        if isFromExcel {
            return Self.excelTypes.contains(type)
        }
        if dropsFileURL, type == PasteboardType.fileURL {
            return false
        }
        return !Self.officeLinkTypes.contains(type)
    }
}
