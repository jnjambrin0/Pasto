import AppKit

/// Where a modal permission window sits while the user deals with the system.
enum PermissionWindowLevel {
    /// How the system's own Accessibility prompts are identified.
    static let accessibilityPromptPrefix = "com.apple.accessibility"

    /// A modal window floats over everything else. It steps down while System Settings is in
    /// front, so the user can answer there, and, if `includesAccessibilityPrompts`, while the
    /// system's Accessibility prompt is.
    static func level(frontmostBundleIdentifier: String?, includesAccessibilityPrompts: Bool) -> NSWindow.Level {
        guard let frontmostBundleIdentifier else { return .modalPanel }
        let isSystemInterface = frontmostBundleIdentifier == SystemSettingsPane.bundleIdentifier
            || includesAccessibilityPrompts && frontmostBundleIdentifier.hasPrefix(accessibilityPromptPrefix)
        return isSystemInterface ? .normal : .modalPanel
    }
}
