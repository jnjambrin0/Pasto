import Foundation
import os
import PastoFoundation

/// Turns what is copied into the clipboard history.
///
/// It takes every settled change `SystemPasteboard` hands over (already past the capture rules),
/// classifies and hashes it, stores it (or moves the item that already holds that content to
/// the front), lets expired items go and tells whoever listens what happened. Changes are dealt
/// with one at a time, in the order they were copied.
///
/// A read that stands for two or more changes of the pasteboard and leaves the history's newest
/// item as it was is not announced: a burst that ends with what was already on top makes no
/// sound and moves no selection.
public actor HistoryManager {
    private let pasteboard: SystemPasteboard
    private let writer: StoreWriter
    private let config: ConfigStore
    private let linkMetadataProvider: (any LinkMetadataProviding)?
    private let now: @Sendable () -> Date
    private let log = Log.logger(.pasteboard)

    private var capturing: Task<Void, Never>?
    private var listeners: [UUID: AsyncStream<CaptureEvent>.Continuation] = [:]

    /// Whether capture is paused. Nothing copied while paused is captured, not even afterwards.
    public private(set) var isPaused = false

    /// - Parameters:
    ///   - linkMetadataProvider: Describes the pages of captured links; without one, links
    ///     keep only what the pasteboard said about them.
    ///   - now: The clock that stamps captured items and decides what has expired.
    public init(
        pasteboard: SystemPasteboard,
        writer: StoreWriter,
        config: ConfigStore,
        linkMetadataProvider: (any LinkMetadataProviding)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.pasteboard = pasteboard
        self.writer = writer
        self.config = config
        self.linkMetadataProvider = linkMetadataProvider
        self.now = now

        if config.value(for: .pasteboardChangeToken) == 0 {
            config.set(pasteboard.changeToken, for: .pasteboardChangeToken)
        }
    }

    deinit {
        capturing?.cancel()
    }

    /// Starts capturing. Does nothing if already started.
    public func start() {
        guard capturing == nil else { return }
        let changes = pasteboard.changes()
        if isPaused {
            pasteboard.stopMonitoring()
        }
        capturing = Task { [weak self] in
            for await change in changes {
                await self?.handle(change)
            }
        }
    }

    /// Pauses or resumes capture. Pausing stops watching the pasteboard altogether; on resuming,
    /// what is on it counts as already seen.
    public func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        // Before `start()` there is nothing to stop; `start()` honours the flag.
        guard capturing != nil else { return }
        if paused {
            pasteboard.stopMonitoring()
        } else {
            pasteboard.startMonitoring()
        }
    }

    /// What happens from now on. Every caller gets its own stream.
    public func events() -> AsyncStream<CaptureEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    private func publish(_ event: CaptureEvent) {
        listeners.values.forEach { $0.yield(event) }
    }

    // MARK: - Capture

    private func handle(_ change: SystemPasteboard.Change) async {
        guard !change.isAccessNeeded else {
            publish(.pasteboardAccessNeeded)
            return
        }

        let timestamp = now()
        guard var item = await NewItem.captured(from: change.items, at: timestamp) else {
            log.error("Error creating item for pasteboard content")
            return
        }
        do {
            item.sourceApplication = try await sourceApplication(for: change.frontmostApplication)
            let outcome = try await writer.perform(author: .capture) { [item] context in
                let outcome = try context.record(item)
                // Adding to the history is what makes old items expire.
                try context.trimHistory(at: timestamp)
                return outcome
            }
            // Saved: the writer has no reason to keep a copy of what was captured in memory.
            try await writer.perform(author: .capture) { $0.releaseContent(of: outcome.id) }
            // Unless the pasteboard has moved on, this is the content the next launch starts from.
            if pasteboard.changeToken == change.changeCount {
                config.set(change.changeCount, for: .pasteboardChangeToken)
            }
            if case .link(let link) = item.preview {
                fetchMetadata(of: link.url, for: outcome.id)
            }
            log.debug("Captured \(change.coveredChangeCount) pasteboard change(s) as \(outcome.id.rawValue, privacy: .public)")
            guard change.coveredChangeCount < 2 || outcome.didChangeNewestItem else { return }
            publish(.captured(PasteboardCapture(
                itemID: outcome.id,
                itemType: item.type,
                wasInHistory: outcome.kind == .movedToFront,
                didChangeNewestItem: outcome.didChangeNewestItem
            )))
        } catch {
            log.error("Capture failed: \(error)")
        }
    }

    /// Asks the page of a link item for its title, icon and image, and returns once they are
    /// stored or known not to come. For a link whose content was rebuilt outside a capture — an
    /// edit of its address — and so lost them.
    public func fetchLinkMetadata(of url: URL, for id: ItemID) async {
        await fetchMetadata(of: url, for: id)?.value
    }

    /// Asks the link's page for its title, icon and image and adds them to the item when — and
    /// if — they arrive. Every capture of a link asks again, a re-copy included: its preview
    /// was just rebuilt without them. The setting is read now, not when the answer comes.
    ///
    /// - Returns: The request under way; `nil` when link previews are off.
    @discardableResult
    private func fetchMetadata(of url: URL, for id: ItemID) -> Task<Void, Never>? {
        guard let linkMetadataProvider, config.value(for: .isLinkPreviewsEnabled) else { return nil }
        return Task { [writer, log] in
            guard let metadata = await linkMetadataProvider.metadata(for: url) else { return }
            do {
                try await writer.perform(author: .capture) { try $0.setLinkMetadata(metadata, of: id, for: url) }
            } catch {
                log.error("Storing link metadata failed: \(error)")
            }
        }
    }

    /// The item's source: the application that was in front, with the icon and colour the store
    /// has for it unless its icon has changed.
    private func sourceApplication(for application: FrontmostApplication?) async throws -> SourceApplication? {
        guard let application, let bundleIdentifier = application.bundleIdentifier else { return nil }
        let stored = try await writer.perform(author: .capture) {
            try $0.sourceApplication(bundleIdentifier: bundleIdentifier)
        }
        return SourceApplicationResolver.sourceApplication(for: application, stored: stored)
    }
}
