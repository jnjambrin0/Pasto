import AppKit
import ProbeCore

/// Puts a string on the pasteboard as a promise and only produces it, after a delay, when some
/// reader asks. Used to test how a clipboard manager captures slow lazily provided data.
final class LazyCopySource: NSObject, NSPasteboardItemDataProvider, Sendable {
    private let delayMs: Int
    private let text: String
    private let log: EventLog

    init(delayMs: Int, sequence: Int, log: EventLog) {
        self.delayMs = delayMs
        self.text = "ProbeTarget lazy string #\(sequence) (provided after \(delayMs) ms)"
        self.log = log
    }

    @MainActor
    func copy(to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setDataProvider(self, forTypes: [.string])
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        log.record("lazyCopyDeclared", ["changeCount": pasteboard.changeCount, "delayMs": delayMs])
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        log.record("lazyDataRequested", ["type": type.rawValue])
        ProbeClock.sleep(ms: Double(delayMs))
        item.setString(text, forType: type)
        log.record("lazyDataProvided", ["type": type.rawValue, "length": text.utf16.count])
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        log.record("lazyProviderFinished")
    }
}
