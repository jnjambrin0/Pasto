import AppKit

/// An installed application whose copies Pasto does not capture.
struct IgnoredApplication: Identifiable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage

    var id: String { bundleIdentifier }

    /// Nil when no application with that identifier is installed: such entries (the partial
    /// identifiers of the default list among them) stay in the setting but are not listed.
    init?(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        self.bundleIdentifier = bundleIdentifier
        name = FileManager.default.displayName(atPath: url.path)
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}
