import AppKit

/// Writes what is restored on a named pasteboard exactly as the app writes the general one —
/// promised image copies included — so that `Tools/CaptureBench` measures a paste without
/// touching the user's clipboard.
@_spi(Benchmarks)
public final class NamedPasteboardWriter: PasteboardWriting, @unchecked Sendable {
    public let pasteboard: NSPasteboard
    private let source: GeneralPasteboardSource

    public init(name: String) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        source = GeneralPasteboardSource(pasteboard: pasteboard)
    }

    public func write(_ items: [PasteboardItemSnapshot]) -> Int {
        source.write(items)
    }

    public var promisesPendingImageCopies: Bool {
        source.promisesPendingImageCopies
    }

    /// Lets the pasteboard go for good.
    public func release() {
        pasteboard.releaseGlobally()
    }
}
