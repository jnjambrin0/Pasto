import CoreGraphics
import Foundation
import ImageIO

/// The stored preview of an image item.
enum ImageThumbnail {
    enum Format: Equatable {
        case png
        case jpeg
    }

    /// The box, in points, a thumbnail has to fit in. An image that already fits keeps its
    /// size; a thumbnail is never larger than its image.
    static let fitSize = CGSize(width: 280, height: 230)

    /// Compression factor of a thumbnail stored as JPEG.
    static let jpegQuality = 0.6

    /// The transparency test stretches the thumbnail over a square bitmap of this side…
    private static let transparencySampleSide = 32
    /// …counts the pixels whose alpha is at most this…
    private static let transparentAlpha: UInt8 = 249
    /// …and calls the image transparent when they are at least this fraction of all.
    private static let transparentFraction = 0.05

    /// The preview of the image in `data`, or `nil` if it cannot be decoded.
    static func preview(of data: Data) -> ImagePreview? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0
        else { return nil }

        let pixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        let pointSize = ImageFitting.pointSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight, properties: properties)
        let thumbnailSize = thumbnailPixelSize(pixelSize: pixelSize, pointSize: pointSize)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(thumbnailSize.width, thumbnailSize.height),
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)

        // The size the card states is in points, whole ones.
        return ImagePreview(
            width: Int(pointSize.width),
            height: Int(pointSize.height),
            byteCount: data.count,
            thumbnailData: thumbnail.flatMap(encode)
        )
    }

    /// How many pixels the thumbnail of an image gets.
    static func thumbnailPixelSize(pixelSize: CGSize, pointSize: CGSize) -> CGSize {
        ImageFitting.pixelSize(fitting: fitSize, pixelSize: pixelSize, pointSize: pointSize)
    }

    /// PNG keeps transparency; anything opaque is smaller as JPEG.
    static func format(for image: CGImage) -> Format {
        isTransparent(image) ? .png : .jpeg
    }

    /// An image without an alpha channel is opaque whatever its pixels say; one with it is
    /// transparent only if enough of it is see-through.
    static func isTransparent(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        let side = transparencySampleSide
        guard let sample = RGBABitmap(drawing: image, width: side, height: side) else { return false }
        let transparentPixels = stride(from: 3, to: sample.bytes.count, by: 4).count { sample.bytes[$0] <= transparentAlpha }
        return Double(transparentPixels) >= transparentFraction * Double(side * side)
    }

    private static func encode(_ image: CGImage) -> Data? {
        let format = format(for: image)
        let type = format == .png ? PasteboardType.png : PasteboardType.jpeg
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return nil }

        let properties: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
