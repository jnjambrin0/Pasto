import AppKit
import CoreGraphics

/// Screen recording permission, needed only by intelligent suggestions, which look at the
/// window the user is about to paste into.
public enum ScreenRecordingAccess {
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time; afterwards the user must change it in System Settings.
    @discardableResult
    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// The state now and after every change, looked at again each time an application becomes
    /// active: the user grants it in System Settings and then comes back.
    public static func states() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var last = isGranted
                continuation.yield(last)
                let activations = NSWorkspace.shared.notificationCenter
                    .notifications(named: NSWorkspace.didActivateApplicationNotification)
                    .map { _ in }
                for await _ in activations {
                    let current = isGranted
                    if current != last {
                        last = current
                        continuation.yield(current)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
