/// What restoring needs from the general pasteboard.
///
/// Synchronous on purpose: a paste reads, composes and writes in one turn of the main actor, so
/// that nothing — a second Return, say — can happen between the write and the ⌘V that follows it.
/// The implementation therefore has to be safe to call from any thread without suspending.
public protocol PasteboardWriting: Sendable {
    /// Replaces the pasteboard contents with `items` and returns the resulting change count,
    /// which the implementation remembers as Pasto's own write so that capture skips it.
    func write(_ items: [PasteboardItemSnapshot]) -> Int

    /// Whether `write` takes the file URL of a temporary image copy still being written as a
    /// promise, handed over once the copy is done (`PendingImageCopy`). Without it, every
    /// copy is written before the pasteboard is.
    var promisesPendingImageCopies: Bool { get }
}

extension PasteboardWriting {
    public var promisesPendingImageCopies: Bool { false }
}
