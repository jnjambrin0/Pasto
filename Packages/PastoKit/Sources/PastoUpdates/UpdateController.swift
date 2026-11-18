import Foundation
import Observation
import os
import PastoFoundation
import Sparkle

/// Pasto's software updates: Sparkle's standard updater and interface behind a type of our own,
/// so no other module sees Sparkle. `PastoApp` creates it at launch and starts it once onboarding
/// is over. On development builds and runs it never starts.
@Observable
public final class UpdateController {
    /// Why updates are off on this run; `nil` when the updater runs.
    public let suppression: UpdaterSuppression?

    /// Whether a check can start now: false while a check or an update session is under way,
    /// and always false while the updater is off.
    public private(set) var canCheckForUpdates = false

    /// Checks on Sparkle's schedule. Sparkle keeps the choice in Pasto's preferences; it starts
    /// on because of `SUEnableAutomaticChecks` in the Info.plist.
    public var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Downloads and installs updates found by scheduled checks without asking. Off until the
    /// user ticks the option in Sparkle's update window.
    public var automaticallyDownloadsUpdates = false {
        didSet {
            guard let updater, updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    @ObservationIgnored private let delegate = UpdaterDelegate()
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let log = Log.logger(.updates)

    private var updater: SPUUpdater? {
        controller?.updater
    }

    /// - Parameters:
    ///   - bundle: The app bundle, whose Info.plist carries the feed and the public key.
    ///   - isDebugBuild: A Debug build never looks for updates.
    ///   - isDevelopmentRun: Nor does a run with the store in memory.
    public init(bundle: Bundle = .main, isDebugBuild: Bool, isDevelopmentRun: Bool) {
        suppression = UpdaterSuppression.reason(
            infoDictionary: bundle.infoDictionary ?? [:],
            isDebugBuild: isDebugBuild,
            isDevelopmentRun: isDevelopmentRun
        )
    }

    /// Starts the updater, which from then on checks on its schedule; the first check of a new
    /// installation happens at once. Calling it again does nothing.
    public func start() {
        guard controller == nil else { return }
        if let suppression {
            log.info("Updates are off on this run: \(String(describing: suppression), privacy: .public)")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: delegate
        )
        self.controller = controller
        observe(controller.updater)
    }

    /// "Check for Updates…": Sparkle's window comes to the front with the progress and then the
    /// result. Does nothing while `canCheckForUpdates` is false.
    public func checkForUpdates() {
        guard let controller, canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    /// Keeps the observable properties in step with the updater, whose properties are
    /// KVO-compliant and change on the main thread.
    private func observe(_ updater: SPUUpdater) {
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.update(from: updater) }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.update(from: updater) }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.update(from: updater) }
            },
        ]
    }

    /// Assigns only what changed, so observers are not woken up for nothing and the setters do
    /// not write the value back.
    private func update(from updater: SPUUpdater) {
        if canCheckForUpdates != updater.canCheckForUpdates {
            canCheckForUpdates = updater.canCheckForUpdates
        }
        if automaticallyChecksForUpdates != updater.automaticallyChecksForUpdates {
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        }
        if automaticallyDownloadsUpdates != updater.automaticallyDownloadsUpdates {
            automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        }
    }
}
