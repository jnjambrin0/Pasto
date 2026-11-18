import CoreGraphics

/// The application in front when the pasteboard was read: what the capture rules judge and what
/// an item's source is taken from.
public struct FrontmostApplication: Sendable {
    public var bundleIdentifier: String?
    /// The localized name.
    public var name: String?
    /// The icon, rendered for `ApplicationIcon.size`.
    public var icon: CGImage?

    public init(bundleIdentifier: String?, name: String?, icon: CGImage?) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.icon = icon
    }
}

/// Tells which application is in front. The workspace and running applications belong to the
/// main thread, so this is asked there; `SystemPasteboard` hops to it once per read.
@MainActor
public protocol FrontmostApplicationProviding: Sendable {
    /// The application that receives key events right now, if there is one.
    func frontmostApplication() -> FrontmostApplication?
}
