import AppKit

/// Puts seed items on a pasteboard the way an ordinary app would when the user copies.
@MainActor
public enum SeedWriter {
    /// Replaces the pasteboard contents with `item` and returns the resulting change count.
    public static func write(_ item: SeedItem, to pasteboard: NSPasteboard = .general, fixtures: URL) throws -> Int {
        let objects: [NSPasteboardWriting]
        switch item.payload {
        case .text(let text):
            objects = [pasteboardItem { $0.setString(text, forType: .string) }]
        case .richText(let plain, let rtf, let html):
            objects = [pasteboardItem {
                $0.setData(Data(rtf.utf8), forType: .rtf)
                $0.setString(html, forType: .html)
                $0.setString(plain, forType: .string)
            }]
        case .url(let address):
            objects = [pasteboardItem {
                $0.setString(address, forType: .URL)
                $0.setString(address, forType: .string)
            }]
        case .image(let image):
            let png = try image.pngData()
            objects = [pasteboardItem { $0.setData(png, forType: .png) }]
        case .files(let files):
            objects = try files.map { try $0.materialize(in: fixtures) as NSURL }
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else {
            throw ProbeError.runtime("the pasteboard rejected seed item \(item.id)")
        }
        return pasteboard.changeCount
    }

    private static func pasteboardItem(_ fill: (NSPasteboardItem) -> Void) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        fill(item)
        return item
    }
}
