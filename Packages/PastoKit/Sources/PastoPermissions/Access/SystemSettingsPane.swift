import AppKit

/// The panes of System Settings › Privacy & Security where the user grants what Pasto needs.
@MainActor
enum SystemSettingsPane: String {
    case accessibility = "Privacy_Accessibility"
    case pasteboard = "Privacy_Pasteboard"
    case screenRecording = "Privacy_ScreenCapture"

    nonisolated static let bundleIdentifier = "com.apple.systempreferences"

    func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Brings System Settings forward with all its windows, if it is running.
    static func activate() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?
            .activate(options: .activateAllWindows)
    }
}
