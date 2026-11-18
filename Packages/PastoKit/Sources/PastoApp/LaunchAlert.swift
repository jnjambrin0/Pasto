import AppKit

/// Runs an alert of the launch so that it is seen.
///
/// Pasto is a menu bar app: while it launches it is not the active app, and macOS treats
/// activation as a request it may turn down — always so for a login item. A modal alert of an
/// inactive app opens behind the windows of the app in use, and the launch waits on it with no
/// menu bar icon yet: Pasto looks half-open. This alert floats above ordinary windows, does not
/// hide when the app is not active, and comes forward on the Space in use.
@MainActor
enum LaunchAlert {
    static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        alert.layout()
        let window = alert.window
        window.level = .modalPanel
        window.hidesOnDeactivate = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        window.orderFrontRegardless()
        return alert.runModal()
    }
}
