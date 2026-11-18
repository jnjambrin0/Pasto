import Foundation

/// What `SystemPasteboard` needs from a pasteboard: `NSPasteboard.general` in the app, an
/// in-memory stand-in in tests.
///
/// Reads come from `SystemPasteboard`'s queue and writes from whichever thread calls
/// `SystemPasteboard.write(_:)`, so an implementation must tolerate both at once.
///
/// SPI for `Tools/CaptureBench`, which measures capture over a pasteboard of its own.
@_spi(Benchmarks)
public protocol PasteboardSource: Sendable {
    var changeCount: Int { get }

    /// Whether Pasto may read the contents without the system asking the user first.
    var allowsProgrammaticReads: Bool { get }

    /// The items currently on the pasteboard, or `nil` when they cannot be read.
    func items() -> [any PasteboardSourceItem]?

    /// The pasteboard-level string for `type` (what `NSPasteboard.string(forType:)` returns).
    func string(forType type: String) -> String?

    /// Replaces the contents and returns the change count that results.
    func write(_ items: [PasteboardItemSnapshot]) -> Int

    /// Whether `write` hands over the file URL of an image copy still being written as a
    /// promise (`PendingImageCopy`). Only a real pasteboard can.
    var promisesPendingImageCopies: Bool { get }
}

@_spi(Benchmarks)
extension PasteboardSource {
    public var promisesPendingImageCopies: Bool { false }
}

/// One item on the pasteboard, before any of its data has been fetched.
@_spi(Benchmarks)
public protocol PasteboardSourceItem {
    var types: [String] { get }

    /// Fetches one representation. If its owner promised it lazily, this is what makes the owner
    /// produce it.
    func data(forType type: String) -> Data?
}
