import AppKit
import os
import PastoFoundation
import PastoOnboarding
import Synchronization

/// Follows the launch phase by phase until the app is ready.
///
/// Each phase is logged at the `notice` level, which the system keeps, and written to the launch
/// record on disk (`last-launch.json`), so that a launch that stops half-way can be told apart
/// later: from the log, from the record, and from a report in the diagnostics folder. A watchdog
/// off the main thread writes that report when a phase that does not wait for the user goes on
/// for longer than its limit, saying how long the main thread has gone without answering.
@MainActor
final class LaunchSequence {
    private static let heartbeatInterval: TimeInterval = 0.5

    private let log = Log.logger(.app)
    private let records: LaunchRecordStore
    private let reports: DiagnosticReportStore
    private var record: LaunchRecord
    private let watchdog: LaunchWatchdog
    private var heartbeat: Timer?
    /// The record on disk is this copy's: other copies were settled with.
    private var isClaimed = false

    init(
        wasLaunchedAsLoginItem: Bool,
        records: LaunchRecordStore = LaunchRecordStore(),
        reports: DiagnosticReportStore = DiagnosticReportStore()
    ) {
        self.records = records
        self.reports = reports
        record = LaunchRecord(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            version: Self.version,
            startedAt: Date(),
            wasLaunchedAsLoginItem: wasLaunchedAsLoginItem,
            location: Self.locationName
        )
        watchdog = LaunchWatchdog(record: record, reports: reports)
        log.notice("""
            Launch: Pasto \(self.record.version, privacy: .public) started from \(self.record.location, privacy: .public)\
            \(wasLaunchedAsLoginItem ? " as a login item" : "", privacy: .public)
            """)
        watchdog.start()
        startHeartbeat()
    }

    var phase: LaunchPhase { record.phase }
    var isReady: Bool { record.isReady }

    /// The launch moves on to `phase`.
    func enter(_ phase: LaunchPhase) {
        guard phase != record.phase, !record.isReady else { return }
        let now = Date()
        let previous = record.phase
        let previousDuration = record.secondsInPhase(at: now)
        record.enter(phase, at: now)
        let elapsed = Int((now.timeIntervalSince(record.startedAt) * 1000).rounded())
        log.notice("""
            Launch phase: \(phase.rawValue, privacy: .public) at +\(elapsed, privacy: .public) ms \
            (\(previous.rawValue, privacy: .public) took \(Self.format(previousDuration), privacy: .public) s)
            """)
        watchdog.update(record)
        persist()
        if phase == .ready {
            heartbeat?.invalidate()
            heartbeat = nil
            watchdog.stop()
        }
    }

    /// This copy goes on: from now on the record on disk is its own. What the previous launch
    /// left there is looked at first; one that went away before it was ready leaves a report.
    func claim() {
        guard !isClaimed else { return }
        isClaimed = true
        if let previous = records.load(),
           previous.processIdentifier != record.processIdentifier,
           !Self.isPastoRunning(previous.processIdentifier) {
            switch previous.ending {
            case .ready:
                break
            case .quit(let phase):
                log.notice("Launch: the previous launch (\(previous.version, privacy: .public)) quit during \(phase.rawValue, privacy: .public)")
            case .interrupted(let phase):
                log.error("""
                    Launch: the previous launch (\(previous.version, privacy: .public)) stopped during \
                    \(phase.rawValue, privacy: .public), before it was ready
                    """)
                save(LaunchReport(kind: .previousLaunchInterrupted, record: previous, secondsInPhase: nil))
            }
        }
        persist()
    }

    /// The app is quitting.
    func didQuit() {
        record.markQuit()
        watchdog.update(record)
        // Only while the record on disk is still this copy's: a copy that gives way, or that
        // another replaces, must not write over the one that goes on.
        guard isClaimed, records.load()?.processIdentifier == record.processIdentifier else { return }
        persist()
    }

    /// The user opened Pasto again while it is still launching — nothing seemed to happen.
    /// Whatever the launch waits on comes forward: an alert, or the welcome window.
    func bringPendingWindowForward() {
        log.notice("Launch: opened again during \(self.record.phase.rawValue, privacy: .public)")
        NSApp.activate()
        let window = NSApp.modalWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    // MARK: - Writing

    private func persist() {
        guard isClaimed else { return }
        do {
            try records.save(record)
        } catch {
            log.error("Launch: could not write the launch record: \(error)")
        }
    }

    private func save(_ report: LaunchReport) {
        do {
            let url = try reports.save(report.encoded(), as: .launch, at: Date())
            log.notice("Launch: wrote \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Launch: could not write a launch report: \(error)")
        }
    }

    // MARK: - Heartbeat

    /// A timer of the main run loop, in every mode — alerts included — tells the watchdog the
    /// main thread is answering.
    private func startHeartbeat() {
        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [watchdog] _ in
            watchdog.beat()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    // MARK: - What the record says

    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static var locationName: String {
        switch ApplicationLocation.current().problem {
        case nil: "applications"
        case .translocated: "translocated"
        case .readOnlyVolume: "readOnlyVolume"
        case .outsideApplications: "outsideApplications"
        }
    }

    private static func isPastoRunning(_ processIdentifier: Int32) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else { return false }
        return !application.isTerminated && application.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    fileprivate nonisolated static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds)
    }
}

/// Checks the launch once a second from the cooperative pool, so that it notices a main thread
/// that is blocked as well as one that is waiting on something that never comes.
private nonisolated final class LaunchWatchdog: Sendable {
    private static let interval: Duration = .seconds(1)

    private struct State {
        var record: LaunchRecord
        var lastBeat = Date()
        /// The start of the phase the last report was about: one report per phase.
        var reportedPhaseStart: Date?
        var task: Task<Void, Never>?
    }

    private let state: Mutex<State>
    private let reports: DiagnosticReportStore

    init(record: LaunchRecord, reports: DiagnosticReportStore) {
        state = Mutex(State(record: record))
        self.reports = reports
    }

    func start() {
        let task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                self?.check()
            }
        }
        state.withLock { $0.task = task }
    }

    func stop() {
        state.withLock { state in
            state.task?.cancel()
            state.task = nil
        }
    }

    func update(_ record: LaunchRecord) {
        state.withLock { $0.record = record }
    }

    func beat() {
        state.withLock { $0.lastBeat = Date() }
    }

    private func check() {
        let now = Date()
        let stalled = state.withLock { state -> (LaunchRecord, TimeInterval)? in
            guard state.record.isStalled(at: now), state.reportedPhaseStart != state.record.phaseStartedAt else { return nil }
            state.reportedPhaseStart = state.record.phaseStartedAt
            return (state.record, now.timeIntervalSince(state.lastBeat))
        }
        guard let (record, silence) = stalled else { return }
        let seconds = record.secondsInPhase(at: now)
        let log = Log.logger(.app)
        log.fault("""
            Launch stalled: \(record.phase.rawValue, privacy: .public) for \(LaunchSequence.format(seconds), privacy: .public) s; \
            main thread silent for \(LaunchSequence.format(silence), privacy: .public) s
            """)
        do {
            let report = LaunchReport(kind: .stalled, record: record, secondsInPhase: seconds, mainThreadSilence: silence)
            let url = try reports.save(report.encoded(), as: .launch, at: now)
            log.notice("Launch: wrote \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Launch: could not write a launch report: \(error)")
        }
    }
}
