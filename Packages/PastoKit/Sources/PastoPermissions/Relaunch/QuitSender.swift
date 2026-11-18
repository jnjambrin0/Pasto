import AppKit
import Darwin

/// The process that asked Pasto to quit.
public enum QuitSender: Equatable, Sendable {
    /// System Settings, or one of its extensions: the Privacy & Security pane's "Quit & Reopen".
    case systemSettings
    /// Any other process, by bundle identifier or, without one, executable path.
    case other(String)
    /// The sender could not be told: it has already gone, or it hid itself.
    case unknown

    /// The bundle identifiers of System Settings, of its panes' extensions and of the old
    /// preference panes.
    static let systemSettingsBundlePrefixes = ["com.apple.systempreferences", "com.apple.settings.", "com.apple.preference."]

    init(bundleIdentifier: String?, executablePath: String?) {
        if let bundleIdentifier, Self.systemSettingsBundlePrefixes.contains(where: bundleIdentifier.hasPrefix) {
            self = .systemSettings
        } else if let executablePath, executablePath.contains("/System Settings.app/")
                    || executablePath.contains("/SecurityPrivacyExtension.appex/") {
            self = .systemSettings
        } else if let name = bundleIdentifier ?? executablePath {
            self = .other(name)
        } else {
            self = .unknown
        }
    }

    init(processIdentifier: pid_t) {
        guard processIdentifier > 0 else {
            self = .unknown
            return
        }
        let path = Self.executablePath(of: processIdentifier)
        // An extension is not always a "running application": its bundle, two folders up from
        // the executable, names it.
        let bundleIdentifier = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
            ?? path.flatMap(Self.bundleIdentifier(ofExecutableAt:))
        self.init(bundleIdentifier: bundleIdentifier, executablePath: path)
    }

    private static func executablePath(of processIdentifier: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// `…/Name.appex/Contents/MacOS/Name` → the bundle identifier of `…/Name.appex`.
    static func bundleIdentifier(ofExecutableAt path: String) -> String? {
        let bundleURL = URL(filePath: path).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: bundleURL)?.bundleIdentifier
    }
}
