import AppKit
import Carbon.HIToolbox

/// What the system says about where a paste would go.
enum SystemDestination {
    /// The bundle identifier of the frontmost application, unless that is Pasto itself.
    static func frontmostApplication() -> String? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return application.bundleIdentifier
    }

    /// Some application has secure input on: a password field has the keyboard.
    static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    /// Whether `bundleIdentifier` belongs to an application on the user's ignore list, which
    /// is the one capture uses: an entry matches when the identifier contains it.
    static func isIgnored(_ bundleIdentifier: String, by entries: [String]) -> Bool {
        // An empty entry would be contained in every identifier.
        entries.contains { !$0.isEmpty && bundleIdentifier.contains($0) }
    }
}
