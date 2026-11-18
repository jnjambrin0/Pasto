import AppKit

/// macOS pasteboard privacy: whether Pasto may read the general pasteboard programmatically.
///
/// A clipboard manager reads the pasteboard without a user-initiated paste, which is exactly
/// what this protection gates. Until the user chooses "Always Allow" for Pasto in System
/// Settings › Privacy & Security › Paste from Other Apps, the system may ask on every read.
public enum PasteboardAccess: Sendable, Equatable {
    /// Pasto has never triggered the system's access alert, so it is not listed in System Settings yet.
    case undetermined
    /// The system asks the user on programmatic reads.
    case ask
    case alwaysAllowed
    case alwaysDenied

    private static let pollInterval: Duration = .milliseconds(500)

    public static var current: PasteboardAccess {
        switch NSPasteboard.general.accessBehavior {
        case .default: .undetermined
        case .ask: .ask
        case .alwaysAllow: .alwaysAllowed
        case .alwaysDeny: .alwaysDenied
        @unknown default: .undetermined
        }
    }

    /// Whether Pasto can capture: anything short of "always allow" interrupts the user.
    public static var isAlwaysAllowed: Bool {
        current == .alwaysAllowed
    }

    /// Whether capture is allowed, now and after every change, asked twice a second.
    public static func states() -> AsyncStream<Bool> {
        AccessPolling.states(every: pollInterval) { isAlwaysAllowed }
    }

    /// The choice System Settings holds, now and after every change, asked twice a second.
    public static func choices() -> AsyncStream<PasteboardAccess> {
        AccessPolling.states(every: pollInterval) { current }
    }

    /// Reads the pasteboard while the user has not decided yet, which is what makes the system
    /// show its alert and list Pasto in System Settings. What is read is thrown away. A state
    /// this SDK does not know is left alone.
    @MainActor
    static func provokeSystemAlertIfUndetermined() {
        guard NSPasteboard.general.accessBehavior == .default else { return }
        _ = NSPasteboard.general.pasteboardItems
    }
}
