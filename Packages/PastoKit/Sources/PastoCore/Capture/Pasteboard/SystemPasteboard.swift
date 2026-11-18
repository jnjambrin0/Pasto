import Foundation
import os
import PastoFoundation

/// The single owner of the general pasteboard.
///
/// It polls the change count, waits for a change to settle, asks the capture rules whether the
/// change is wanted, reads every representation that is, and publishes the result. It also
/// performs Pasto's own writes, remembering their change count so that Pasto never captures
/// what it has just written.
///
/// ## Threads and locking
///
/// - **Polling, debounce and reads** run on `queue`, a private serial queue. `pendingSync`
///   belongs to that queue: it is only touched from blocks running on it.
/// - **Writes** run synchronously on the caller's thread — the main thread, when the user
///   pastes — so that "write, post ⌘V, deactivate" is one uninterrupted turn.
/// - **Reads are handed over on the main queue**: a read is dropped there if Pasto wrote at or
///   after it and, since pastes happen on that same thread, none can slip in between that check
///   and the hand-over.
/// - Everything else that is mutable (the change tokens, the poll timer, the stream's
///   continuation) lives in `state` and is only reached inside its lock. The lock is never held
///   while reading the pasteboard, asking the rules or yielding to the stream; a write holds it
///   for as long as it takes, so a poll or a read never sees a pasteboard that Pasto has written
///   but not yet accounted for.
public final class SystemPasteboard: @unchecked Sendable {
    private struct State {
        var tracker: PasteboardChangeTracker
        /// Present while monitoring.
        var pollTimer: (any DispatchSourceTimer)?
        var continuation: AsyncStream<Change>.Continuation?
        /// Tells the current consumer of `changes()` from the ones it replaced.
        var consumer = 0
    }

    /// Serial and user-initiated. Not private so that tests can wait for it.
    let queue: DispatchQueue
    let source: any PasteboardSource
    private let configuration: Configuration
    private let config: ConfigStore
    private let applications: any FrontmostApplicationProviding
    private let log = Log.logger(.pasteboard)

    private let state: OSAllocatedUnfairLock<State>
    /// The read waiting for the pasteboard to settle. Confined to `queue`.
    private var pendingSync: DispatchWorkItem?

    /// - Parameters:
    ///   - config: Where the ignore lists come from, and where the change token and the read
    ///     count are kept.
    ///   - applications: Tells which application is in front when a read begins.
    public convenience init(
        configuration: Configuration = .standard,
        config: ConfigStore = ConfigStore(),
        applications: any FrontmostApplicationProviding = WorkspaceFrontmostApplication()
    ) {
        self.init(source: GeneralPasteboardSource(), configuration: configuration, config: config, applications: applications)
    }

    /// Over any pasteboard: tests and `Tools/CaptureBench` use one of their own.
    @_spi(Benchmarks)
    public init(
        source: any PasteboardSource,
        configuration: Configuration,
        config: ConfigStore,
        applications: any FrontmostApplicationProviding
    ) {
        // Each block drains its own autorelease pool: what `NSPasteboard` hands over while a large
        // copy is read is let go of when that read ends, not whenever the thread next idles.
        self.queue = DispatchQueue(label: "\(Log.subsystem).pasteboard", qos: .userInitiated, autoreleaseFrequency: .workItem)
        self.source = source
        self.configuration = configuration
        self.config = config
        self.applications = applications

        // Until monitoring starts and takes its own baseline, the token is the one the last
        // session left, or the live count if there is none.
        let storedToken = config.value(for: .pasteboardChangeToken)
        let tracker = PasteboardChangeTracker(
            changeToken: storedToken != 0 ? storedToken : source.changeCount,
            droppedSyncWindow: configuration.droppedSyncWindow
        )
        self.state = OSAllocatedUnfairLock(uncheckedState: State(tracker: tracker))
    }

    /// The last change count Pasto saw, read or wrote.
    public var changeToken: Int {
        state.withLockUnchecked { $0.tracker.changeToken }
    }

    // MARK: - Consuming changes

    /// Starts monitoring and returns the stream of settled changes.
    ///
    /// There is one consumer: asking again ends the stream handed out before. Monitoring stops
    /// when the consumer stops listening.
    public func changes() -> AsyncStream<Change> {
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self)
        let (replaced, consumer) = state.withLockUnchecked { state in
            let replaced = state.continuation
            state.continuation = continuation
            state.consumer += 1
            return (replaced, state.consumer)
        }
        replaced?.finish()
        continuation.onTermination = { [weak self] _ in self?.consumerDidStop(consumer) }
        startMonitoring()
        return stream
    }

    private func consumerDidStop(_ consumer: Int) {
        let wasCurrent = state.withLockUnchecked { state in
            guard state.consumer == consumer else { return false }
            state.continuation = nil
            return true
        }
        if wasCurrent {
            stopMonitoring()
        }
    }

    // MARK: - Monitoring

    /// Starts polling. Whatever is on the pasteboard at this point counts as seen: it is not
    /// captured, neither at launch nor when monitoring resumes after a pause. Does nothing if
    /// already monitoring.
    public func startMonitoring() {
        let timer = state.withLockUnchecked { state -> (any DispatchSourceTimer)? in
            guard state.pollTimer == nil else { return nil }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            state.pollTimer = timer
            return timer
        }
        guard let timer else { return }
        log.info("Start monitoring pasteboard")

        // Queued ahead of the first tick, which is one interval away.
        queue.async { [weak self] in self?.takeBaseline() }
        timer.schedule(
            deadline: .now() + configuration.pollInterval,
            repeating: configuration.pollInterval,
            leeway: configuration.pollLeeway
        )
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
    }

    /// Stops polling: this is how capture is paused. A read that is waiting for the pasteboard
    /// to settle does nothing when its time comes, as long as monitoring is still stopped; one
    /// that has already begun is still delivered.
    public func stopMonitoring() {
        let timer = state.withLockUnchecked { state in
            defer { state.pollTimer = nil }
            return state.pollTimer
        }
        guard let timer else { return }
        log.info("Stop monitoring pasteboard")
        timer.cancel()
    }

    private func takeBaseline() {
        let changeCount = source.changeCount
        state.withLockUnchecked { $0.tracker.startMonitoring(changeCount: changeCount) }
    }

    private func poll() {
        let changeCount = source.changeCount
        switch state.withLockUnchecked({ $0.tracker.poll(changeCount: changeCount) }) {
        case .unchanged:
            return
        case .changed:
            break
        case .mayHaveBeenFilled:
            guard let items = source.items(), !items.isEmpty else { return }
            state.withLockUnchecked { $0.tracker.contentAppeared() }
        }

        log.debug("Pasteboard change detected, starting sync timer")
        pendingSync?.cancel()
        let sync = DispatchWorkItem { [weak self] in self?.syncTimerFired() }
        pendingSync = sync
        queue.asyncAfter(deadline: .now() + configuration.settleDelay, execute: sync)
    }

    // MARK: - Reading

    private func syncTimerFired() {
        pendingSync = nil
        guard state.withLockUnchecked({ $0.pollTimer != nil }) else { return }
        log.debug("Sync timer fired")

        // The frontmost application is main-thread state; the read itself goes back to the queue.
        Task { [weak self, applications] in
            let frontmost = await applications.frontmostApplication()
            guard let self else { return }
            queue.async { self.synchronize(frontmost: frontmost) }
        }
    }

    /// Reads whatever is on the pasteboard now. It does not matter which change scheduled the
    /// read: the tokens are stamped with the live change count, and a change that arrives while
    /// reading is simply found by the next poll.
    private func synchronize(frontmost: FrontmostApplication?) {
        log.info("Starting pasteboard sync from \(frontmost?.bundleIdentifier ?? "unknown", privacy: .private)")
        let changeCount = source.changeCount
        let read = state.withLockUnchecked { $0.tracker.beginRead(changeCount: changeCount, at: Date()) }

        let outcome = PasteboardReader(maximumSize: configuration.maximumCaptureSize).read(
            source,
            frontmostBundleIdentifier: frontmost?.bundleIdentifier,
            rules: CaptureRules(config: config)
        )
        switch outcome {
        case .accessNeeded:
            // The tokens have moved: this change will not be looked at again.
            log.notice("Pasteboard access is not allowed, skipping pasteboard change")
            DispatchQueue.main.async { [weak self] in self?.reportAccessNeeded(for: read, frontmost: frontmost) }
        case .unreadable:
            log.error("Error reading system pasteboard items")
        case .skipped(let reason):
            state.withLockUnchecked { $0.tracker.cancelRead(read, at: Date()) }
            if case .ignoredSource(let source) = reason {
                // What the copying application declared is pasteboard content, not metadata.
                log.info("Cancelling pasteboard sync: ignored declared source \(source, privacy: .private)")
            } else {
                log.info("Cancelling pasteboard sync: \(String(describing: reason), privacy: .public)")
            }
        case .read(let items, let pasteboardWasEmpty):
            state.withLockUnchecked { $0.tracker.acceptRead(read, isEmpty: pasteboardWasEmpty) }
            log.debug("Pasteboard sync completed")
            DispatchQueue.main.async { [weak self] in self?.deliver(read, items: items, frontmost: frontmost) }
        }
    }

    /// Main queue. Hands a read to the consumer unless Pasto has written since.
    private func deliver(_ read: PasteboardChangeTracker.Read, items: [PasteboardItemSnapshot], frontmost: FrontmostApplication?) {
        let (isReplaced, continuation) = state.withLockUnchecked { state in
            (state.tracker.isReplacedByOwnWrite(read), state.continuation)
        }
        guard !isReplaced else {
            log.info("Dropping pasteboard read replaced by own write")
            return
        }
        guard let continuation else { return }

        config.set(config.value(for: .pasteboardSyncCount) + 1, for: .pasteboardSyncCount)
        guard !items.isEmpty else {
            // Nothing to capture; the consumer stores the token itself once it has captured.
            config.set(read.token, for: .pasteboardChangeToken)
            log.info("Empty pasteboard content")
            return
        }
        continuation.yield(Change(
            changeCount: read.token,
            coveredChangeCount: read.coveredChanges,
            frontmostApplication: frontmost,
            items: items,
            isAccessNeeded: false
        ))
    }

    /// Main queue. Tells the consumer that a change could not be read, which is what lets the app
    /// ask the user for access.
    private func reportAccessNeeded(for read: PasteboardChangeTracker.Read, frontmost: FrontmostApplication?) {
        state.withLockUnchecked { $0.continuation }?.yield(Change(
            changeCount: read.token,
            coveredChangeCount: read.coveredChanges,
            frontmostApplication: frontmost,
            items: [],
            isAccessNeeded: true
        ))
    }

    // MARK: - Writing

    /// Replaces the pasteboard contents and returns the resulting change count.
    ///
    /// Synchronous, and safe to call from any thread. What is written is never captured, and a
    /// read that was under way is discarded: it holds either this content or content this write
    /// has replaced.
    @discardableResult
    public func write(_ items: [PasteboardItemSnapshot]) -> Int {
        state.withLockUnchecked { state in
            let changeCount = source.write(items)
            state.tracker.didWrite(changeCount: changeCount)
            return changeCount
        }
    }
}
