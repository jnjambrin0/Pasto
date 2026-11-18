import CoreGraphics
import Foundation
import ImageIO

/// Decodes the encoded images of card models (thumbnails, icons, link previews) and keeps the
/// results, so that a cell scrolled back into view gets its image at once.
///
/// The images of a card are small — a stored thumbnail, an application or site icon — so they
/// are decoded as the card is configured and are there from its first frame. That holds up to
/// `inlineDecodingByteLimit`; anything larger is decoded off the main actor.
///
/// One decoder is shared by all the cells of a strip; the collection creates it and passes it in
/// `ItemCellEnvironment`.
public nonisolated final class ImageDecoder: Sendable {
    /// Encoded images up to this size are decoded where they are asked for.
    public static let inlineDecodingByteLimit = 512 * 1024

    /// What the decoded bitmaps kept in memory may add up to. A card thumbnail decodes to about
    /// 1 MB, so this keeps some seventy of them — eight screenfuls of image cards — and scrolling
    /// through 5000 of them stays within 70 MB above what the app uses at rest.
    public static let defaultByteLimit = 64 * 1024 * 1024

    /// `NSCache` is safe to use from any thread, which the type system cannot see.
    private nonisolated(unsafe) let cache = NSCache<CacheKey, CachedImage>()
    /// Empties the cache when the system runs short of memory: every image in it can be decoded again.
    private let memoryPressure: any DispatchSourceMemoryPressure

    /// `byteLimit` bounds the decoded bitmaps kept in memory.
    public init(byteLimit: Int = ImageDecoder.defaultByteLimit) {
        cache.totalCostLimit = byteLimit
        memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        memoryPressure.setEventHandler { [weak self] in
            self?.removeAllImages()
        }
        memoryPressure.activate()
    }

    deinit {
        memoryPressure.cancel()
    }

    /// Lets go of every decoded image; cells that need one again decode it again.
    func removeAllImages() {
        cache.removeAllObjects()
    }

    /// The decoded image if it is already in memory. Never decodes, so it is safe while scrolling.
    public func cachedImage(for data: Data, maxPixelSize: Int? = nil) -> CGImage? {
        cache.object(forKey: CacheKey(data: data, maxPixelSize: maxPixelSize))?.image
    }

    /// Decodes `data` right away, on the caller's thread: for an image no larger than
    /// `inlineDecodingByteLimit`, which is quick.
    public func decodedImage(for data: Data, maxPixelSize: Int? = nil) -> CGImage? {
        let key = CacheKey(data: data, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) { return cached.image }
        guard let image = Self.decode(data, maxPixelSize: maxPixelSize) else { return nil }
        cache.setObject(CachedImage(image), forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    /// Decodes `data`, scaled down so that neither side exceeds `maxPixelSize`. The bitmap is
    /// fully decompressed before it is returned, so drawing it later costs nothing.
    @concurrent
    public func image(for data: Data, maxPixelSize: Int? = nil) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return decodedImage(for: data, maxPixelSize: maxPixelSize)
    }

    /// The size of an encoded image, read from its header.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return (width, height)
    }

    private static func decode(_ data: Data, maxPixelSize: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let maxPixelSize else {
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

/// Identifies a decoded image by its encoded bytes and the size it was decoded at.
private nonisolated final class CacheKey: NSObject {
    private let data: Data
    private let maxPixelSize: Int?

    init(data: Data, maxPixelSize: Int?) {
        self.data = data
        self.maxPixelSize = maxPixelSize
    }

    // `Data` hashes a bounded prefix, so this stays cheap for large images.
    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(data)
        hasher.combine(maxPixelSize)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CacheKey else { return false }
        return maxPixelSize == other.maxPixelSize && data == other.data
    }
}

private nonisolated final class CachedImage {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
