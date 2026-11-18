import Foundation
import os

/// A temporary image copy that is still being written when the pasteboard is.
///
/// Pasting an image that only came as TIFF gives it a PNG copy in a file. Encoding a large one
/// takes seconds, and a paste writes the pasteboard and queues the ⌘V in one turn of the main
/// thread. So for a large TIFF the copy is encoded in the background, and the pasteboard gets the
/// file URL as a promise (`NSPasteboardItemDataProvider`): whoever reads it — the application the
/// ⌘V lands in, typically — waits until the file is complete, exactly as it would have waited for
/// the paste itself. The order of the paste does not change: the pasteboard is written, with every
/// type, before the ⌘V.
///
/// The processor plans the copy (`begin`), the pasteboard writer takes the plan by the URL it put
/// in the item (`take`), and the background work finishes it.
final class PendingImageCopy: Sendable {
    /// Where the copy was planned; its URL is what the item carries until the copy is done.
    let plannedURL: URL

    private let done = DispatchSemaphore(value: 0)
    private let file = OSAllocatedUnfairLock<URL?>(initialState: nil)

    private static let pending = OSAllocatedUnfairLock<[String: PendingImageCopy]>(initialState: [:])

    /// How long a reader waits for the copy at most: far more than the largest copy takes.
    static let waitLimit: DispatchTimeInterval = .seconds(60)

    private init(plannedURL: URL) {
        self.plannedURL = plannedURL
    }

    /// Plans a copy at `url`, written by `work` in the background; `work` returns the file it
    /// wrote, or `nil` if it could not write one. Only for a pasteboard writer that takes every
    /// plan of the items it is given (`PasteboardWriting.promisesPendingImageCopies`).
    static func begin(at url: URL, work: @escaping @Sendable () -> URL?) -> PendingImageCopy {
        let copy = PendingImageCopy(plannedURL: url)
        pending.withLock { $0[url.absoluteString] = copy }
        DispatchQueue.global(qos: .userInitiated).async {
            let written = work()
            copy.file.withLock { $0 = written }
            copy.done.signal()
        }
        return copy
    }

    /// The copy an item's file URL stands for, if it is one still being written; it is handed
    /// over once.
    static func take(forURLData data: Data) -> PendingImageCopy? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        return pending.withLock { $0.removeValue(forKey: string) }
    }

    /// Waits until the copy is written and returns its file; `nil` if it could not be written or
    /// took longer than `waitLimit`.
    func waitForFile() -> URL? {
        guard done.wait(timeout: .now() + Self.waitLimit) == .success else { return nil }
        done.signal()
        return file.withLock { $0 }
    }
}
