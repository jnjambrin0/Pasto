import Foundation
import os
import PastoFoundation

/// Puts items of the history back on the general pasteboard: what pasting and copying from Pasto
/// have in common.
///
/// **Isolation.** `restore` is synchronous and runs start to finish on the main actor: it reads
/// the items, composes what to write, writes the temporary image copies and writes the
/// pasteboard, in that order, without suspending. That is deliberate. A paste is "restore, queue
/// the ⌘V, deactivate" in one turn; if any of it were awaited, the panel would stay interactive
/// in between and a second Return would paste twice. Three things are left to run later, because
/// nothing the paste needs depends on them:
/// - the clean-up of old temporary copies, on a background queue;
/// - the PNG copy of a large image that came as TIFF only, encoded in the background while the
///   pasteboard holds its file URL as a promise that whoever reads it waits for;
/// - the history update, in a task that goes through the store's single writer and therefore
///   queues behind any capture that is being saved.
@MainActor
public final class ItemRestorer {
    private let reader: StoreReader
    private let writer: StoreWriter
    private let pasteboard: any PasteboardWriting
    private let config: ConfigStore
    private let now: @Sendable () -> Date
    private let imageDirectory: TemporaryImageDirectory
    private let composer: PasteboardItemComposer
    private let log = Log.logger(.paste)

    /// Called at the end of every restore, inside `restore` itself: for what has to happen in
    /// the same turn as the pasteboard write and before whatever the caller does next — the
    /// paste sound, which precedes the keystroke. `events()` reports the same thing a turn later.
    public var onRestore: ((RestoreEvent) -> Void)?

    private var eventContinuation: AsyncStream<RestoreEvent>.Continuation?

    /// The history update of the latest restore, which runs after the ones before it.
    private(set) var historyUpdate: Task<Void, Never>?

    /// - Parameters:
    ///   - now: The clock that stamps the restored items and ages the temporary image copies.
    ///   - temporaryDirectory: Where the `images` folder of the temporary copies lives.
    ///   - environment: The process environment, which decides whether an image restored on its
    ///     own gets a temporary copy.
    public init(
        reader: StoreReader,
        writer: StoreWriter,
        pasteboard: any PasteboardWriting,
        config: ConfigStore,
        now: @escaping @Sendable () -> Date = { Date() },
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.reader = reader
        self.writer = writer
        self.pasteboard = pasteboard
        self.config = config
        self.now = now
        imageDirectory = TemporaryImageDirectory(temporaryDirectory: temporaryDirectory)
        composer = PasteboardItemComposer(
            includesSingleImageFile: PasteboardItemProcessor.includesSingleImageFile(environment: environment)
        )
    }

    /// Every restore, as it happens. There is one consumer: asking again ends the previous stream.
    public func events() -> AsyncStream<RestoreEvent> {
        eventContinuation?.finish()
        let (stream, continuation) = AsyncStream.makeStream(of: RestoreEvent.self)
        eventContinuation = continuation
        return stream
    }

    /// Writes the items to the pasteboard, in the order given, and moves them to the front of the
    /// history. When it returns the pasteboard holds them, `onRestore` has run and the event has
    /// been published; the history follows.
    ///
    /// - Parameter options: Final: the "always paste as plain text" setting is the caller's to
    ///   apply (`RestoreOptions.applying(alwaysPlainText:)`), because not every caller honours it.
    /// - Returns: `false` when there was nothing to restore — no identifiers, or none of an item
    ///   that still exists — in which case nothing was touched.
    public func restore(_ ids: [ItemID], options: RestoreOptions) -> Bool {
        let restored = restorableItems(ids)
        guard !restored.isEmpty else { return false }

        // A large TIFF's PNG copy is encoded after the write, when the pasteboard can promise
        // its file; the write and the ⌘V that follows stay in this turn.
        let defersLargeConversions = pasteboard.promisesPendingImageCopies
        let snapshots = composer.compose(restored.map(\.item), options: options) { includesSingleImageFile in
            PasteboardItemProcessor(
                includesSingleImageFile: includesSingleImageFile,
                defersLargeConversions: defersLargeConversions,
                directory: imageDirectory,
                now: now
            )
        }
        let changeCount = pasteboard.write(snapshots)
        config.set(changeCount, for: .pasteboardChangeToken)

        let restoredIDs = restored.map(\.id)
        updateHistory(for: restoredIDs)
        let event = RestoreEvent(itemIDs: restoredIDs)
        onRestore?(event)
        eventContinuation?.yield(event)
        return true
    }

    /// What dragging the items out of Pasto carries: for every item that still exists, its part
    /// of what a restore of all of them would write, composed together and with a temporary file
    /// for every image. Several items with some text merge into one element, which the first item
    /// carries; the others carry nothing and travel as their identifier alone. Nothing else
    /// happens: the general pasteboard and the history are left alone.
    ///
    /// - Parameter ids: In the order of the drag, which is the order of the merged text.
    public func draggingContents(of ids: [ItemID], options: RestoreOptions) -> [ItemID: [PasteboardItemSnapshot]] {
        let restored = restorableItems(ids)
        let composer = PasteboardItemComposer(includesSingleImageFile: true)
        let composed = composer.composeByItem(restored.map(\.item), options: options) { includesSingleImageFile in
            PasteboardItemProcessor(includesSingleImageFile: includesSingleImageFile, directory: imageDirectory, now: now)
        }
        return Dictionary(zip(restored.map(\.id), composed), uniquingKeysWith: { first, _ in first })
    }

    /// Deletes every temporary image copy, whatever its age. The app calls it when it starts — for
    /// what an earlier run left behind, a crashed one included — and when it quits, so that no
    /// image of the history outlives Pasto in the temporary directory. The 24-hour clean-up of
    /// every paste still applies while it runs.
    ///
    /// Synchronous and safe from any thread; it only deletes a handful of files.
    ///
    /// - Parameter temporaryDirectory: The one the restorer was created with.
    public nonisolated static func removeTemporaryImageCopies(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        TemporaryImageDirectory(temporaryDirectory: temporaryDirectory).removeAll()
    }

    /// The items among `ids` that still exist, in the order given, with what they hold.
    private func restorableItems(_ ids: [ItemID]) -> [(id: ItemID, item: RestorableItem)] {
        reader.items(ids).compactMap { item in
            guard let pasteboardItems = reader.pasteboardItems(for: item.id) else { return nil }
            return (item.id, RestorableItem(item, pasteboardItems: pasteboardItems, now: now))
        }
    }

    private func updateHistory(for ids: [ItemID]) {
        let previous = historyUpdate
        historyUpdate = Task { [writer, now, log] in
            // Restores reach the history in the order they happened.
            await previous?.value
            do {
                try await writer.perform(author: .user) { context in
                    try context.moveToFrontOfHistory(ids, clock: now)
                }
            } catch {
                log.error("Could not update the history after a restore: \(error)")
            }
        }
    }
}
