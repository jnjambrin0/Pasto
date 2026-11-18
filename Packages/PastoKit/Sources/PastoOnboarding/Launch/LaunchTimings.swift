import AppKit
import CoreServices

/// The waits of the launch sequence.
public nonisolated enum LaunchTimings {
    /// Before anything else, when the system started Pasto as a login item: the session is
    /// still coming up.
    public static let loginItemDelay: Duration = .seconds(5)
    /// Between the end of a first launch and showing the panel.
    public static let panelRevealDelay: Duration = .milliseconds(100)

    /// Whether the system started Pasto as a login item. Only meaningful while the application
    /// is handling the event that launched it, in `applicationDidFinishLaunching`.
    @MainActor
    public static var wasLaunchedAsLoginItem: Bool {
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        return launchEvent?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}
