import AppKit
import os
import PastoFoundation
import Sparkle

/// Sparkle's delegate for both the updater and its standard interface. It declares support for
/// gentle reminders and logs failures; Sparkle then shows an update found by a scheduled check
/// behind the active app, without taking focus, except right after launch.
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let log = Log.logger(.updates)

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Pasto is a menu bar app: an update the user asked for must come to the front over
        // whichever app is active. Sparkle 2.10 activates the app itself; this keeps it so.
        guard handleShowingUpdate, state.userInitiated else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        log.error("Update aborted: \(error.localizedDescription, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        log.error("Could not download \(item.displayVersionString, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        log.info("No update: \(error.localizedDescription, privacy: .public)")
    }
}
