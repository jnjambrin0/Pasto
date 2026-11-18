/// Restoring writes through the same object that watches the pasteboard, so that the write is
/// recorded as Pasto's own and never captured back.
extension SystemPasteboard: PasteboardWriting {
    public var promisesPendingImageCopies: Bool {
        source.promisesPendingImageCopies
    }
}
