import AppKit
import Darwin
import os
import PastoFoundation
import PastoOnboarding

extension ConfigKey where Value == Bool {
    /// "Don't ask again", ticked when declining to move a copy that runs from a writable folder
    /// outside Applications. A disk image or a translocated copy is asked about every time all
    /// the same.
    static var moveToApplicationsFolderAlertSuppress: ConfigKey<Bool> {
        ConfigKey("moveToApplicationsFolderAlertSuppress", default: false)
    }
}

/// Offers to move Pasto into an Applications folder when it runs from a disk image, from where
/// macOS put a download it translocated, or from any folder outside Applications. Runs first
/// thing at launch on Release builds, before anything is registered from the running copy: a
/// login item, the updater.
///
/// Moving copies the bundle to `/Applications` (or `~/Applications` without write access
/// there), replacing an older copy, takes the quarantine mark off the copy, moves the
/// downloaded one to the Trash when it can, opens the new copy and quits. No AppleScript and no
/// administrator rights: what the user cannot do in Finder without a password is not tried.
@MainActor
final class ApplicationRelocator {
    enum Outcome {
        /// Go on launching this copy.
        case launch
        /// This copy is done: another took over, or the user chose to quit.
        case quit
    }

    private enum Choice {
        case move, dontMove, quit
    }

    /// A failure of Pasto's own, worded when it happens.
    private struct RelocationError: LocalizedError {
        let errorDescription: String?
    }

    private static let quarantineAttribute = "com.apple.quarantine"
    private static let otherCopyQuitTimeout: Duration = .seconds(5)
    /// Opening the moved copy; past this, this copy goes on.
    private static let openTimeout: Duration = .seconds(10)

    private let config: ConfigStore
    private let location = ApplicationLocation.current()
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private let log = Log.logger(.app)

    init(config: ConfigStore) {
        self.config = config
    }

    /// Whether this copy is somewhere it should be moved from, and the user is to be asked.
    var isNeeded: Bool {
        guard let problem = location.problem else { return false }
        return problem != .outsideApplications || !config.value(for: .moveToApplicationsFolderAlertSuppress)
    }

    func run() async -> Outcome {
        guard isNeeded, let problem = location.problem else { return .launch }
        log.notice("Pasto runs from \(String(describing: problem), privacy: .public): \(self.location.bundleURL.path, privacy: .private)")

        let translocatedOriginal = problem == .translocated
            ? Self.translocatedOriginalURL(of: location.bundleURL).map { ($0, ApplicationLocation.isOnReadOnlyVolume($0)) }
            : nil
        let plan = ApplicationRelocation.plan(
            for: location,
            translocatedOriginal: translocatedOriginal,
            isSystemApplicationsFolderWritable: FileManager.default.isWritableFile(
                atPath: ApplicationLocation.applicationsFolders(homeDirectory: homeDirectory).system.path
            ),
            homeDirectory: homeDirectory
        )
        guard let plan else {
            // Translocated, and macOS would not say where the user's copy is.
            return askToMoveByHand()
        }
        switch askToMove(problem) {
        case .dontMove: return .launch
        case .quit: return .quit
        case .move: break
        }
        do {
            return try await move(plan)
        } catch is CancellationError {
            return .launch
        } catch {
            log.error("Could not move Pasto to \(plan.destination.path, privacy: .private): \(error)")
            showFailure(error)
            return .launch
        }
    }

    // MARK: - Moving

    /// Moves the copy and opens the new one: `.quit` when it opened, `.launch` when it did not
    /// answer in time — this copy then goes on, and a new copy that does open later gives way
    /// to it (`SingleInstance`).
    private func move(_ plan: ApplicationRelocation) async throws -> Outcome {
        let fileManager = FileManager.default
        if plan.copiesBundle {
            try fileManager.createDirectory(at: plan.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: plan.destination.path) {
                if let running = runningCopy(at: plan.destination) {
                    guard confirmReplacingRunningCopy() else { throw CancellationError() }
                    try await quit(running)
                }
                // The older copy goes to the Trash, where it can still be got back.
                try fileManager.trashItem(at: plan.destination, resultingItemURL: nil)
            }
            try fileManager.copyItem(at: plan.source, to: plan.destination)
        }
        // A copy that keeps the mark would be translocated again when opened.
        Self.removeQuarantine(from: plan.destination)
        if let original = plan.originalToTrash {
            do {
                try fileManager.trashItem(at: original, resultingItemURL: nil)
            } catch {
                // The new copy is in place: a download left behind is no reason to stop.
                log.error("Could not move the downloaded copy to the Trash: \(error)")
            }
        }
        let destination = plan.destination
        let opened = try await Deadline.run(within: Self.openTimeout) {
            let configuration = NSWorkspace.OpenConfiguration()
            // This copy, with the same bundle identifier, is still running: without this the
            // system would bring it forward instead of opening the new one.
            configuration.createsNewApplicationInstance = true
            _ = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
            return true
        }
        guard opened == true else {
            log.error("Pasto moved to \(destination.path, privacy: .private), but the new copy did not open in time: this copy goes on")
            return .launch
        }
        log.notice("Pasto moved to \(destination.path, privacy: .private); quitting this copy")
        return .quit
    }

    /// Another Pasto open from where the new copy is to go.
    private func runningCopy(at url: URL) -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first { application in
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && application.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == destination
        }
    }

    private func quit(_ application: NSRunningApplication) async throws {
        application.terminate()
        let deadline = ContinuousClock.now + Self.otherCopyQuitTimeout
        while !application.isTerminated {
            guard ContinuousClock.now < deadline else {
                throw RelocationError(errorDescription: AppStrings.relocationOtherCopyStillRunning)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Takes the quarantine mark off the bundle and everything in it. A file without the mark
    /// is left as it is.
    private static func removeQuarantine(from bundle: URL) {
        var paths = [bundle.path]
        if let enumerator = FileManager.default.enumerator(atPath: bundle.path) {
            for case let relativePath as String in enumerator {
                paths.append(bundle.appending(path: relativePath).path)
            }
        }
        for path in paths {
            removexattr(path, quarantineAttribute, XATTR_NOFOLLOW)
        }
    }

    /// Where the user's copy of a translocated app really is. `SecTranslocateCreateOriginalPathForURL`
    /// is in Security.framework but has no public header, so it is looked up at run time; nil
    /// when it is not there or fails.
    private static func translocatedOriginalURL(of translocatedURL: URL) -> URL? {
        typealias CreateOriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        let createOriginalPath = unsafeBitCast(symbol, to: CreateOriginalPath.self)
        var error: Unmanaged<CFError>?
        guard let original = createOriginalPath(translocatedURL as CFURL, &error)?.takeRetainedValue() else {
            error?.release()
            return nil
        }
        return original as URL
    }

    // MARK: - Alerts

    private func askToMove(_ problem: ApplicationLocation.Problem) -> Choice {
        let alert = NSAlert()
        alert.messageText = AppStrings.relocationTitle
        alert.informativeText = location.isEphemeral ? AppStrings.relocationEphemeralMessage : AppStrings.relocationOutsideMessage
        alert.addButton(withTitle: AppStrings.relocationMove)
        alert.addButton(withTitle: AppStrings.relocationDontMove).keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: AppStrings.quit)
        // Only a copy that stays where it is can be left there for good.
        if problem == .outsideApplications {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = AppStrings.relocationDontAskAgain
        }
        let response = LaunchAlert.runModal(alert)
        switch response {
        case .alertFirstButtonReturn:
            return .move
        case .alertSecondButtonReturn:
            if alert.suppressionButton?.state == .on {
                config.set(true, for: .moveToApplicationsFolderAlertSuppress)
            }
            return .dontMove
        default:
            return .quit
        }
    }

    private func askToMoveByHand() -> Outcome {
        let alert = NSAlert()
        alert.messageText = AppStrings.relocationByHandTitle
        alert.informativeText = AppStrings.relocationByHandMessage
        alert.addButton(withTitle: AppStrings.quit)
        alert.addButton(withTitle: AppStrings.relocationDontMove).keyEquivalent = "\u{1b}"
        return LaunchAlert.runModal(alert) == .alertFirstButtonReturn ? .quit : .launch
    }

    private func confirmReplacingRunningCopy() -> Bool {
        let alert = NSAlert()
        alert.messageText = AppStrings.relocationReplaceTitle
        alert.informativeText = AppStrings.relocationReplaceMessage
        alert.addButton(withTitle: AppStrings.relocationReplace)
        alert.addButton(withTitle: AppStrings.relocationCancel).keyEquivalent = "\u{1b}"
        return LaunchAlert.runModal(alert) == .alertFirstButtonReturn
    }

    private func showFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppStrings.relocationFailureTitle
        alert.informativeText = AppStrings.relocationFailureMessage(error.localizedDescription)
        alert.addButton(withTitle: AppStrings.relocationOK)
        _ = LaunchAlert.runModal(alert)
    }
}
