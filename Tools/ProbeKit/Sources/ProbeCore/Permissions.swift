import AppKit
import ApplicationServices

/// The privacy grants the probes depend on. macOS attributes them to the *responsible* process
/// (the terminal app that launched the tool), never to the tool binary itself.
public struct PermissionStatus: Codable, Sendable {
    public struct ResponsibleProcess: Codable, Sendable {
        public let pid: Int32
        public let name: String?
        public let bundleID: String?
    }

    public let accessibility: Bool
    public let postEvent: Bool
    public let listenEvent: Bool
    public let screenCapture: Bool
    /// `NSPasteboard.general.accessBehavior`: `default`, `ask`, `alwaysAllow` or `alwaysDeny`.
    public let pasteboardAccess: String
    public let responsibleProcess: ResponsibleProcess?
}

public enum Permissions {
    /// Reads every grant without ever triggering a system prompt.
    public static func current() -> PermissionStatus {
        PermissionStatus(
            accessibility: AXIsProcessTrusted(),
            postEvent: CGPreflightPostEventAccess(),
            listenEvent: CGPreflightListenEventAccess(),
            screenCapture: CGPreflightScreenCaptureAccess(),
            pasteboardAccess: pasteboardAccessName(NSPasteboard.general.accessBehavior),
            responsibleProcess: responsibleProcess()
        )
    }

    public static func requireAccessibility() throws {
        guard AXIsProcessTrusted() else { throw missing("Accessibility", pane: "Accessibility") }
    }

    public static func requirePostEvent() throws {
        guard CGPreflightPostEventAccess() else { throw missing("Permission to post input events", pane: "Accessibility") }
    }

    public static func requireScreenCapture() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw missing("Screen recording", pane: "Screen & System Audio Recording")
        }
    }

    public static func pasteboardAccessName(_ behavior: NSPasteboard.AccessBehavior) -> String {
        switch behavior {
        case .default: "default"
        case .ask: "ask"
        case .alwaysAllow: "alwaysAllow"
        case .alwaysDeny: "alwaysDeny"
        @unknown default: "unknown(\(behavior.rawValue))"
        }
    }

    private static func missing(_ permission: String, pane: String) -> ProbeError {
        let holder = responsibleProcess().map { "\($0.name ?? "the responsible process") (pid \($0.pid))" }
            ?? "the app that launched this tool"
        return .permission(
            "\(permission) is not granted to \(holder); enable it in System Settings > Privacy & Security > \(pane) and run again"
        )
    }

    /// Looks up the process TCC charges for this tool. `responsibility_get_pid_responsible_for_pid`
    /// is a private libSystem symbol, so it is resolved at run time and treated as optional.
    private static func responsibleProcess() -> PermissionStatus.ResponsibleProcess? {
        typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let symbol = dlsym(defaultHandle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        let pid = unsafeBitCast(symbol, to: ResponsiblePID.self)(getpid())
        guard pid > 0 else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)
        return .init(pid: pid, name: app?.localizedName, bundleID: app?.bundleIdentifier)
    }
}
