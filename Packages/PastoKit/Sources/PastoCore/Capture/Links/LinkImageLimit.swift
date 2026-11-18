import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Link Presentation hands over a page's image no larger than 1024 pixels on its longest side
/// (1200 × 630 arrives as 1024 × 537, 3000 × 1000 as 1024 × 341). Pasto scales a
/// larger one down the same way before `SystemLinkMetadataProvider.reducedImage(of:)`, which
/// goes by points: an image that declares a high resolution has few points for its many pixels
/// and would otherwise be decoded and kept whole.
enum LinkImageLimit {
    static let pixelLimit = 1024

    /// `data` when its image is within the limit, or a PNG of it scaled down to the limit;
    /// `nil` when it is not an image the system can decode.
    static func limited(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        guard max(width, height) > pixelLimit else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelLimit,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
