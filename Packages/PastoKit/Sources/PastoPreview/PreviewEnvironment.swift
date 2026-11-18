import Foundation
import os
import PastoCore
import PastoFoundation

/// What every view of the module works with: the store, the settings and the way out to the
/// rest of the app. One instance, owned by `ItemPreviewCoordinator`.
final class PreviewEnvironment {
    let reader: StoreReader
    let config: ConfigStore
    let handlers: PreviewHandlers

    private let writer: StoreWriter
    /// The writer whose changes the panel's ⌘Z undoes; renames go through it when there is one.
    private let itemWriter: UndoableWriter?
    private let log = Log.logger(.store)
    /// The latest save of an edit. The next one waits for it, so that saves reach the store in
    /// the order they were made even though each first works out its content off the main actor.
    private var lastSave: Task<Void, Never>?

    init(reader: StoreReader, writer: StoreWriter, itemWriter: UndoableWriter?, config: ConfigStore, handlers: PreviewHandlers) {
        self.reader = reader
        self.writer = writer
        self.itemWriter = itemWriter
        self.config = config
        self.handlers = handlers
    }

    // MARK: - Writes

    /// Saves an edit: the item gets the content, type, checksum and preview that follow from
    /// `snapshots`, and keeps its title, its date and its place. Content with nothing to hash
    /// leaves the item untouched. A failure is logged, not shown.
    ///
    /// Content that is a link has a preview rebuilt from the address alone: once it is saved,
    /// its page is asked about again.
    func replaceContent(of id: ItemID, with snapshots: [PasteboardItemSnapshot]) {
        let previous = lastSave
        lastSave = Task {
            await previous?.value
            guard let content = await NewItem.captured(from: snapshots, at: Date()) else { return }
            await write { try $0.replaceContent(of: id, with: content) }
            if case .link(let link) = content.preview {
                handlers.fetchLinkMetadata?(link.url, id)
            }
        }
    }

    /// Renames an item. Like a rename on its card, it is a step of undo when the coordinator was
    /// given the undoable writer.
    func setTitle(_ title: String?, of id: ItemID) {
        let rename: @Sendable (WritingContext) throws -> Void = { try $0.setTitle(title, of: id) }
        Task {
            guard let itemWriter else {
                await write(rename)
                return
            }
            do {
                try await itemWriter.perform(rename)
            } catch {
                log.error("Preview rename failed: \(error)")
            }
        }
    }

    /// Creates an item at the front of `list`: of the history, or of a pinboard without entering
    /// the history (`WritingContext.create`). Content already stored is that item, not a copy.
    func createItem(from snapshots: [PasteboardItemSnapshot], in list: ListID?) async {
        guard let item = await NewItem.captured(from: snapshots, at: Date()) else { return }
        await write { _ = try $0.create(item, in: list ?? .clipboard) }
    }

    private func write(_ work: @escaping @Sendable (WritingContext) throws -> Void) async {
        do {
            try await writer.perform(author: .user, work)
        } catch {
            log.error("Preview write failed: \(error)")
        }
    }
}
