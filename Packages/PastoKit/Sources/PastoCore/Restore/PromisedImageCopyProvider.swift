import AppKit
import os

/// Hands the pasteboard the file URL of a temporary image copy once it is written
/// (`PendingImageCopy`). AppKit asks when someone reads the type, and the reader waits for the
/// answer.
final class PromisedImageCopyProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let copy: PendingImageCopy

    /// The providers on a pasteboard, kept until it is done with them.
    private static let live = OSAllocatedUnfairLock<[ObjectIdentifier: PromisedImageCopyProvider]>(initialState: [:])

    init(_ copy: PendingImageCopy) {
        self.copy = copy
        super.init()
        Self.live.withLock { $0[ObjectIdentifier(self)] = self }
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        // Without a file there is nothing to point at: the type stays empty.
        guard let file = copy.waitForFile() else { return }
        item.setData(Data(file.absoluteString.utf8), forType: type)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        _ = Self.live.withLock { $0.removeValue(forKey: ObjectIdentifier(self)) }
    }
}
