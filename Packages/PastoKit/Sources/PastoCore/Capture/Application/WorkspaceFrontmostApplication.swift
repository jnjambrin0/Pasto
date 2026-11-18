import AppKit

/// The frontmost application according to `NSWorkspace`: the identifier, localized name and icon
/// of the running application.
@MainActor
public struct WorkspaceFrontmostApplication: FrontmostApplicationProviding {
    public nonisolated init() {}

    public func frontmostApplication() -> FrontmostApplication? {
        NSWorkspace.shared.frontmostApplication.map { Self.application($0) }
    }

    /// A running application as capture describes it when it is in front.
    /// - Parameter icon: Drawn instead of the icon the system has for it; Pasto passes its own
    ///   finished icon, which the system's records may not match (`AppIconImage` in `PastoApp`).
    public static func application(_ application: NSRunningApplication, icon: NSImage? = nil) -> FrontmostApplication {
        FrontmostApplication(
            bundleIdentifier: application.bundleIdentifier,
            name: application.localizedName,
            icon: (icon ?? application.icon).flatMap(render)
        )
    }

    /// The representation AppKit picks for the icon at its stored size, without a context or
    /// hints. Proposing the rectangle picks the same representation as setting that size on the
    /// image would, and leaves the shared image untouched.
    private static func render(_ icon: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: ApplicationIcon.size)
        return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
