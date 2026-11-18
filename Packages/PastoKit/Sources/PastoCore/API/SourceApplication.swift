import Foundation

/// The application an item was copied from.
public struct SourceApplication: Sendable, Hashable {
    public var bundleIdentifier: String
    public var name: String
    /// The application's accent color; 0 while it has not been computed.
    public var colorCode: Int64
    public var iconData: Data?

    public init(bundleIdentifier: String, name: String, colorCode: Int64 = 0, iconData: Data? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.colorCode = colorCode
        self.iconData = iconData
    }
}
