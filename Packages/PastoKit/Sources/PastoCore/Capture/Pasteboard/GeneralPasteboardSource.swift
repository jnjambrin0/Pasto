import AppKit
import os
import PastoFoundation

/// The system's general pasteboard.
///
/// `NSPasteboard` declares no thread safety, so Pasto keeps each use in one place: change count
/// and reads on `SystemPasteboard`'s serial queue, writes on the thread that pastes.
struct GeneralPasteboardSource: PasteboardSource, @unchecked Sendable {
    /// The pasteboard refuses a representation of this many bytes or more, and with it the
    /// whole write (on macOS 27.2, 255 MiB goes through and 256 MiB does not). Larger
    /// ones are left out, so that the rest of what is pasted still arrives.
    static let representationSizeLimit = 256 * 1024 * 1024

    private let pasteboard: NSPasteboard

    /// - Parameter pasteboard: The general one in the app; a named one of its own in the benchmark.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// The file URL of an image copy still being written goes on as a promise.
    var promisesPendingImageCopies: Bool { true }

    var changeCount: Int {
        pasteboard.changeCount
    }

    /// Only "always allow" lets a clipboard manager read on every copy without the system asking.
    var allowsProgrammaticReads: Bool {
        pasteboard.accessBehavior == .alwaysAllow
    }

    func items() -> [any PasteboardSourceItem]? {
        pasteboard.pasteboardItems?.map(Item.init)
    }

    func string(forType type: String) -> String? {
        pasteboard.string(forType: NSPasteboard.PasteboardType(type))
    }

    func write(_ items: [PasteboardItemSnapshot]) -> Int {
        // Built before clearing, so other observers see an empty pasteboard for as short a time
        // as possible.
        let pasteboardItems = items.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for type in snapshot.types {
                guard let data = snapshot.dataByType[type] else { continue }
                guard Self.isWritable(byteCount: data.count) else {
                    Log.logger(.paste).notice("Left out \(data.count) bytes of \(type, privacy: .public): too large for the pasteboard")
                    continue
                }
                if type == RestoreMetrics.fileURLType, let copy = PendingImageCopy.take(forURLData: data) {
                    item.setDataProvider(PromisedImageCopyProvider(copy), forTypes: [NSPasteboard.PasteboardType(type)])
                    continue
                }
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(pasteboardItems)
        return pasteboard.changeCount
    }

    static func isWritable(byteCount: Int) -> Bool {
        byteCount < representationSizeLimit
    }

    private struct Item: PasteboardSourceItem {
        let item: NSPasteboardItem

        var types: [String] {
            item.types.map(\.rawValue)
        }

        func data(forType type: String) -> Data? {
            item.data(forType: NSPasteboard.PasteboardType(type))
        }
    }
}
