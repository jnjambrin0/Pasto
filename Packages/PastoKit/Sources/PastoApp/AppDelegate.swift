import AppKit
import os
import PastoCore
import PastoFoundation
import PastoOnboarding
import PastoPermissions

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Log.logger(.app)
    private var coordinator: AppCoordinator?
    private var launch: LaunchSequence?
    private let diagnosticReports = DiagnosticReportCollector()

    /// Before anything can draw the app's icon.
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppIconImage.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read while the launch event is still current.
        let wasLaunchedAsLoginItem = LaunchTimings.wasLaunchedAsLoginItem
        let launch = LaunchSequence(wasLaunchedAsLoginItem: wasLaunchedAsLoginItem)
        self.launch = launch
        log.notice("""
            Launch: accessibility=\(AccessibilityAccess.isGranted, privacy: .public) \
            pasteboard=\(String(describing: PasteboardAccess.current), privacy: .public)
            """)
        diagnosticReports.start()
        Task { await run(launch, wasLaunchedAsLoginItem: wasLaunchedAsLoginItem) }
    }

    /// The launch, in order: other copies, the copy's location, the store, then the app itself.
    /// Every wait on the app has a limit; the waits on the user come to the front.
    private func run(_ launch: LaunchSequence, wasLaunchedAsLoginItem: Bool) async {
        #if DEBUG
        let relocator: ApplicationRelocator? = nil
        #else
        // Before anything is registered from this copy, a login item or the updater: a copy on
        // a disk image or translocated goes away.
        let relocator: ApplicationRelocator? = ApplicationRelocator(config: ConfigStore())
        #endif
        let needsRelocation = relocator?.isNeeded == true

        // Runs with a store in memory may run beside another copy, and keep no launch record.
        if !DebugArguments.usesInMemoryStore {
            launch.enter(.checkingOtherCopies)
            guard await SingleInstance.resolve(needsRelocation: needsRelocation) else { return }
            launch.claim()
        }

        if let relocator, needsRelocation {
            launch.enter(.relocating)
            guard await relocator.run() == .launch else {
                NSApp.terminate(nil)
                return
            }
            // This copy stays where it is. A newer one that went on to replace the running copy,
            // and was not moved after all, gives way to that copy now.
            launch.enter(.checkingOtherCopies)
            guard await SingleInstance.resolve(needsRelocation: false) else { return }
        }
        start(launch, wasLaunchedAsLoginItem: wasLaunchedAsLoginItem)
    }

    private func start(_ launch: LaunchSequence, wasLaunchedAsLoginItem: Bool) {
        launch.enter(.openingStore)
        let services: Services
        do {
            services = try Services(inMemory: DebugArguments.usesInMemoryStore)
        } catch {
            log.fault("Could not open the store: \(error)")
            recover(from: error, launch: launch, wasLaunchedAsLoginItem: wasLaunchedAsLoginItem)
            return
        }
        let coordinator = AppCoordinator(services: services)
        self.coordinator = coordinator
        // On a first launch the coordinator shows the welcome window and waits for it: a wait on
        // the user, which no time limit applies to.
        launch.enter(Self.showsWelcome(config: services.config) ? .welcome : .startingApp)
        Task {
            await coordinator.start(wasLaunchedAsLoginItem: wasLaunchedAsLoginItem)
            launch.enter(.ready)
        }
    }

    /// The coordinator's own decision (`LaunchPlan`), read the same way.
    private static func showsWelcome(config: ConfigStore) -> Bool {
        guard !DebugArguments.usesInMemoryStore, let version = AppVersion(bundle: .main) else { return false }
        return LaunchPlan(lastLaunchedVersion: config.lastLaunchedVersion, currentVersion: version).runsOnboarding
    }

    /// The store did not open. Nothing is ever deleted: a damaged store can be set aside, next
    /// to where it was, and a new one started.
    private func recover(from error: any Error, launch: LaunchSequence, wasLaunchedAsLoginItem: Bool) {
        launch.enter(.storeFailure)
        let reason = (error as? PersistentStack.LoadError)?.reason
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = AppStrings.storeFailureTitle
        switch reason {
        case .migrationFailed:
            alert.informativeText = AppStrings.storeFailureMigration
            alert.addButton(withTitle: AppStrings.storeFailureTryAgain)
        case .createdByNewerVersion:
            alert.informativeText = AppStrings.storeFailureNewerVersion
        default:
            alert.informativeText = AppStrings.storeFailureUnreadable
            alert.addButton(withTitle: AppStrings.storeFailureStartFresh)
        }
        alert.addButton(withTitle: AppStrings.storeFailureShowInFinder)
        alert.addButton(withTitle: AppStrings.quit)

        let response = LaunchAlert.runModal(alert)
        let choice = alert.buttons[response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue].title
        switch choice {
        case AppStrings.storeFailureTryAgain:
            start(launch, wasLaunchedAsLoginItem: wasLaunchedAsLoginItem)
        case AppStrings.storeFailureStartFresh:
            do {
                let folder = try PersistentStack.moveDamagedStoreAside()
                log.notice("Set the damaged store aside in \(folder.lastPathComponent, privacy: .public)")
                start(launch, wasLaunchedAsLoginItem: wasLaunchedAsLoginItem)
            } catch {
                log.fault("Could not set the store aside: \(error)")
                NSWorkspace.shared.activateFileViewerSelecting([PersistentStack.defaultStoreURL])
                NSApp.terminate(nil)
            }
        case AppStrings.storeFailureShowInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([PersistentStack.defaultStoreURL])
            NSApp.terminate(nil)
        default:
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        launch?.didQuit()
        ItemRestorer.removeTemporaryImageCopies()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening Pasto again shows the panel; AppKit has nothing else to do. While the launch is
    /// still going on, what it waits on comes forward instead — an alert, the welcome window —
    /// so that opening it again never seems to do nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let launch, !launch.isReady {
            launch.bringPendingWindowForward()
            return false
        }
        coordinator?.reopen()
        return false
    }
}
