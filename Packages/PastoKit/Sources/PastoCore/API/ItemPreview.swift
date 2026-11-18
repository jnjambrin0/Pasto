import Foundation

/// What a cell needs to draw an item without loading its pasteboard data.
///
/// Capture decides how much goes in here (text truncation, thumbnail size); the store keeps it as
/// an opaque blob.
public enum ItemPreview: Sendable, Hashable, Codable {
    case text(TextPreview)
    case link(LinkPreview)
    case image(ImagePreview)
    case color(ColorPreview)
    case files(FilesPreview)
    case unknown
}

public struct TextPreview: Sendable, Hashable, Codable {
    public var text: String
    /// Length of the full text, which `text` may truncate.
    public var characterCount: Int
    public var richTextData: Data?

    public init(text: String, characterCount: Int, richTextData: Data? = nil) {
        self.text = text
        self.characterCount = characterCount
        self.richTextData = richTextData
    }
}

public struct LinkPreview: Sendable, Hashable, Codable {
    public var url: URL
    public var title: String?
    public var iconData: Data?
    public var imageData: Data?

    public init(url: URL, title: String? = nil, iconData: Data? = nil, imageData: Data? = nil) {
        self.url = url
        self.title = title
        self.iconData = iconData
        self.imageData = imageData
    }
}

public struct ImagePreview: Sendable, Hashable, Codable {
    /// The size of the image in whole points — its pixels at the resolution it declares, or at
    /// 72 dots per inch —, which its card states. A Retina screenshot is half its pixels.
    public var width: Int
    public var height: Int
    public var byteCount: Int
    public var thumbnailData: Data?

    public init(width: Int, height: Int, byteCount: Int, thumbnailData: Data? = nil) {
        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.thumbnailData = thumbnailData
    }
}

public struct ColorPreview: Sendable, Hashable, Codable {
    /// `0xRRGGBB`.
    public var colorCode: UInt64

    public init(colorCode: UInt64) {
        self.colorCode = colorCode
    }
}

public struct FilesPreview: Sendable, Hashable, Codable {
    public var paths: [String]
    /// Size of the first file only; folders are not added up.
    public var totalByteCount: Int64?
    /// Encoded thumbnail or icon of the first file.
    public var thumbnailData: Data?

    public init(paths: [String], totalByteCount: Int64? = nil, thumbnailData: Data? = nil) {
        self.paths = paths
        self.totalByteCount = totalByteCount
        self.thumbnailData = thumbnailData
    }
}
