import AppKit
import os
import PastoFoundation

/// One copy of Pasto at a time: two would capture every copy twice, fight over the shortcuts and
/// open the same store. The decision is `SingleInstancePolicy`'s; this carries it out with the
/// running applications.
///
/// The development build (`jnjambrino.Pasto.dev`) has its own bundle identifier and does not
/// count, nor do runs with a store in memory, which never get here.
@MainActor
enum SingleInstance {
    /// How long an older copy that is on its way out gets to quit: one that moved itself to the
    /// Applications folder opens the new copy and only then quits.
    private static let quitWait: Duration = .seconds(3)
    /// A stuck copy asked to quit, and then made to.
    private static let terminateWait: Duration = .seconds(3)
    private static let forceTerminateWait: Duration = .seconds(2)
    /// Opening the copy that stays, which shows its panel.
    private static let openLimit: Duration = .seconds(5)
    private static let pollInterval: Duration = .milliseconds(100)

    /// Whether this copy is to go on starting. When it is not, the copy that stays has been
    /// brought forward and this one is quitting.
    ///
    /// - Parameter needsRelocation: This copy runs from somewhere it should be moved from; a
    ///   newer version then goes on, so that moving it offers to replace the running copy.
    static func resolve(needsRelocation: Bool, records: LaunchRecordStore = LaunchRecordStore()) async -> Bool {
        let log = Log.logger(.app)
        let me = copy(of: NSRunningApplication.current, record: nil)
        let older = SingleInstancePolicy.olderCopies(than: me, among: running().map { copy(of: $0, record: nil) })
        guard !older.isEmpty else { return true }

        log.notice("Launch: another copy of Pasto is running (pid \(older.map(\.processIdentifier), privacy: .public)); waiting for it to quit")
        let deadline = ContinuousClock.now + quitWait
        while !stillRunning(older).isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
        let record = records.load()
        let remaining = stillRunning(older).map { copy(of: $0, record: record) }

        switch SingleInstancePolicy.decision(for: me, olderCopiesStillRunning: remaining, needsRelocation: needsRelocation) {
        case .proceed:
            log.notice("Launch: the other copy quit")
            return true
        case .proceedToReplace(let processIdentifier):
            log.notice("Launch: this newer copy goes on to replace the one running (pid \(processIdentifier, privacy: .public))")
            return true
        case .replaceStuckCopy(let processIdentifier):
            log.error("Launch: the other copy (pid \(processIdentifier, privacy: .public)) is stuck launching; making it quit")
            if let application = NSRunningApplication(processIdentifier: processIdentifier) {
                await stop(application)
            }
            return true
        case .handOver(let processIdentifier):
            log.notice("Launch: handing over to the copy that is running (pid \(processIdentifier, privacy: .public)) and quitting")
            if let application = NSRunningApplication(processIdentifier: processIdentifier) {
                await bringForward(application)
            }
            NSApp.terminate(nil)
            return false
        }
    }

    // MARK: - Copies

    private static func running() -> [NSRunningApplication] {
        guard let identifier = Bundle.main.bundleIdentifier else { return [] }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != current && !$0.isTerminated }
    }

    private static func stillRunning(_ copies: [SingleInstancePolicy.Copy]) -> [NSRunningApplication] {
        let identifiers = Set(copies.map(\.processIdentifier))
        return running().filter { identifiers.contains($0.processIdentifier) }
    }

    /// `record` is the launch record on disk; it speaks for the copy whose process it names.
    private static func copy(of application: NSRunningApplication, record: LaunchRecord?) -> SingleInstancePolicy.Copy {
        let version = application.bundleURL.flatMap(Bundle.init(url:))?.infoDictionary?["CFBundleShortVersionString"] as? String
        let isStuck = record.map { $0.processIdentifier == application.processIdentifier && $0.isStalled(at: Date()) } ?? false
        return SingleInstancePolicy.Copy(
            processIdentifier: application.processIdentifier,
            launchDate: application.launchDate,
            version: version,
            isStuckLaunching: isStuck
        )
    }

    // MARK: - Acting

    /// Opening the copy that stays again shows its panel, or brings forward what its launch
    /// waits on. A system that does not answer in time does not hold this one back.
    private static func bringForward(_ application: NSRunningApplication) async {
        guard let url = application.bundleURL else {
            application.activate()
            return
        }
        let opened = await Deadline.finishes(within: openLimit) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        if !opened {
            Log.logger(.app).error("Launch: the other copy did not open in time")
            application.activate()
        }
    }

    /// Asks a stuck copy to quit and, if it does not, makes it.
    private static func stop(_ application: NSRunningApplication) async {
        application.terminate()
        guard await waitUntilTerminated(application, for: terminateWait) else {
            application.forceTerminate()
            if await !waitUntilTerminated(application, for: forceTerminateWait) {
                Log.logger(.app).error("Launch: the stuck copy did not quit")
            }
            return
        }
    }

    private static func waitUntilTerminated(_ application: NSRunningApplication, for duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while !application.isTerminated, ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
        return application.isTerminated
    }
}
