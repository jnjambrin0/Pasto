import AppKit
import os
import PastoFoundation

/// Makes sure Pasto comes back after System Settings quits it to apply a screen recording grant.
///
/// System Settings reopens the app itself a few seconds after quitting it (seen in the log on
/// macOS 27.2: the quit event, then LaunchServices launching Pasto again 3.2 s later), but
/// nothing guarantees it, and Apple documents none of it. So while a request is pending, a quit
/// sent by System Settings leaves behind a small shell that waits for this process to end, gives
/// System Settings a few seconds to reopen Pasto, and opens it if it has not
/// (`RelaunchHelper`). Quitting from Pasto's menu, from the Dock or by logging out never
/// relaunches.
///
/// Who asked Pasto to quit is only known while the quit Apple Event is being handled: AppKit's
/// own handler has let go of it by the time the termination notification is posted (as of macOS
/// 27.2). So the relauncher handles that event itself — it notes the request and terminates, as
/// AppKit's handler does — and reads the note as Pasto terminates.
@MainActor
public final class ScreenRecordingRelauncher: NSObject {
    private let config: ConfigStore
    private let log = Log.logger(.app)
    private var observer: (any NSObjectProtocol)?
    /// The quit Apple Event being answered, if that is what is terminating Pasto.
    private var quitRequest: QuitRequest?

    public init(config: ConfigStore) {
        self.config = config
    }

    /// Starts handling the quit Apple Event and watching for termination. Call once, early in
    /// launch, after AppKit has put its own handlers in place.
    public func start() {
        guard observer == nil else { return }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuitEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication)
        )
        // No queue: the block runs in the posting turn, on the main thread, before the process
        // exits.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: NSApp, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationWillTerminate() }
        }
    }

    @objc private func handleQuitEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        quitRequest = QuitRequest(event: event)
        NSApp.terminate(nil)
    }

    private func applicationWillTerminate() {
        guard var request = config.screenRecordingRequest else { return }
        let quit = quitRequest ?? QuitRequest(event: NSAppleEventManager.shared().currentAppleEvent)
        let now = Date()
        guard request.callsForRelaunch(after: quit, at: now) else {
            log.notice("Quitting with a screen recording request pending; no relaunch (\(String(describing: quit), privacy: .public))")
            return
        }
        // The next launch is the reopen: it takes the user back even if the grant has not reached
        // it yet.
        request.relaunchDate = now
        config.set(JSONConfigValue(request), for: .screenRecordingRequest)
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        guard let executable = Bundle.main.executableURL else { return }
        do {
            try RelaunchHelper.openAfterExit(
                of: ProcessInfo.processInfo.processIdentifier,
                application: Bundle.main.bundleURL,
                executable: executable
            )
            log.notice("System Settings quit Pasto for the screen recording grant; Pasto will open again")
        } catch {
            log.error("Could not arrange to open again after quitting: \(error)")
        }
    }
}
