import AppKit
import PastoCore
import UniformTypeIdentifiers

/// What an item hands to the rest of the system: something to open, files to show in Finder,
/// things to share.
enum ItemExternalActions {
    // MARK: - Open

    /// What opening the item opens: a link's address, or the first of its files if it is
    /// still there. `nil` for everything else.
    static func openableURL(of item: Item) -> URL? {
        switch item.preview {
        case .link(let link):
            link.url
        case .files(let files):
            existingFileURLs(files.paths.prefix(1)).first
        case .text, .image, .color, .unknown:
            nil
        }
    }

    /// The name of the application the system opens the item's first file with; `nil` for an
    /// item that is not files or that nothing can open.
    static func openingApplicationName(for item: Item) -> String? {
        guard case .files = item.preview, let url = openableURL(of: item),
              let application = NSWorkspace.shared.urlsForApplications(toOpen: url).first
        else { return nil }
        return FileManager.default.displayName(atPath: application.path)
    }

    /// Opens what can be opened among `items` with the system's default application, and
    /// leaves the panel. False when there was nothing to open.
    static func open(_ items: [Item]) -> Bool {
        let urls = items.compactMap(openableURL)
        guard !urls.isEmpty else { return false }
        NSApp.deactivate()
        urls.forEach { NSWorkspace.shared.open($0) }
        return true
    }

    // MARK: - Reveal in Finder

    /// Shows in Finder the first file of each of `items`, if it still exists, and leaves the
    /// panel. False when there was none.
    static func revealInFinder(_ items: [Item]) -> Bool {
        let urls = items.flatMap { item -> [URL] in
            guard case .files(let files) = item.preview else { return [] }
            return existingFileURLs(files.paths.prefix(1))
        }
        guard !urls.isEmpty else { return false }
        NSApp.deactivate()
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        return true
    }

    private static func existingFileURLs(_ paths: some Sequence<String>) -> [URL] {
        paths.filter(FileManager.default.fileExists(atPath:)).map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Share

    /// What sharing the item shares: text and colours as strings, a link as its address,
    /// files as file addresses, an image as an image. Unknown content shares nothing.
    static func shareableItems(of item: Item, pasteboardItems: [PasteboardItemSnapshot]) -> [Any] {
        switch item.preview {
        case .text, .color:
            pasteboardItems.compactMap(\.plainText)
        case .link(let link):
            [link.url]
        case .files(let files):
            files.paths.map { URL(fileURLWithPath: $0) }
        case .image:
            pasteboardItems.compactMap(image)
        case .unknown:
            []
        }
    }

    /// The image a pasteboard item holds: its first representation that is an image, in the
    /// order the source declared them.
    private static func image(in pasteboardItem: PasteboardItemSnapshot) -> NSImage? {
        for type in pasteboardItem.types where UTType(type)?.conforms(to: .image) == true {
            if let image = pasteboardItem.dataByType[type].flatMap(NSImage.init(data:)) {
                return image
            }
        }
        return nil
    }
}
