import AppKit

/// The process a probe is pointed at, resolved from `--app pasto|pasto-release|<bundle-id>|<pid>`.
public struct TargetApp: Codable, Sendable, Equatable {
    public let pid: Int32
    public let bundleID: String?
    public let name: String?

    /// `pasto` is the development build that `scripts/run.sh` installs, which has an identifier
    /// of its own; `pasto-release`, an installed release.
    public static let aliases: [String: String] = [
        "pasto": "jnjambrino.Pasto.dev",
        "pasto-release": "jnjambrino.Pasto",
    ]

    public static func resolve(_ selector: String) throws -> TargetApp {
        if let pid = Int32(selector) {
            guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else {
                throw ProbeError.targetNotFound("no process with pid \(selector)")
            }
            let app = NSRunningApplication(processIdentifier: pid)
            return TargetApp(pid: pid, bundleID: app?.bundleIdentifier, name: app?.localizedName)
        }
        let bundleID = aliases[selector.lowercased()] ?? selector
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw ProbeError.targetNotFound("no running app with bundle id \(bundleID)")
        }
        return TargetApp(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName)
    }
}
