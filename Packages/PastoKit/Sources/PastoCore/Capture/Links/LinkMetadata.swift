import Foundation

/// What a web page says about itself, as far as a link card shows it.
public struct LinkMetadata: Sendable, Equatable {
    public var title: String?
    /// The site's icon, as PNG.
    public var iconData: Data?
    /// The page's representative image, as PNG.
    public var imageData: Data?

    public init(title: String? = nil, iconData: Data? = nil, imageData: Data? = nil) {
        self.title = title
        self.iconData = iconData
        self.imageData = imageData
    }
}

/// Looks up the metadata of a link. `nil` means the page could not be reached or described.
public protocol LinkMetadataProviding: Sendable {
    func metadata(for url: URL) async -> LinkMetadata?
}
