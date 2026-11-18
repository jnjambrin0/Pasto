import ApplicationServices
import IOKit.hid

/// Accessibility permission, required to post the synthetic ⌘V of direct paste.
public enum AccessibilityAccess {
    private static let pollInterval: Duration = .seconds(1)

    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Whether the user has already answered the system's alert, one way or the other. After
    /// that the system does not ask again: the only way left is System Settings.
    public static var hasSystemDecision: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypePostEvent) != kIOHIDAccessTypeUnknown
    }

    /// Makes the system show its permission alert, by asking for the right to post keyboard
    /// events, which is what the synthetic ⌘V needs. Returns the state at that moment; the user
    /// answers asynchronously.
    @discardableResult
    public static func requestShowingSystemPrompt() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
    }

    /// The state now and after every change. The system offers no notification, so it is asked
    /// once a second.
    public static func states() -> AsyncStream<Bool> {
        AccessPolling.states(every: pollInterval) { isGranted }
    }
}
