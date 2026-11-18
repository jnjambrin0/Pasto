import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The image data a temporary copy is made from.
struct ImageRepresentation {
    let data: Data
    let type: UTType

    /// The first of `RestoreMetrics.imageTypes` that `element` offers; `nil` when it offers none.
    init?(of element: PasteboardItemSnapshot) {
        for type in RestoreMetrics.imageTypes {
            if let data = element.dataByType[type.identifier] {
                self.init(data: data, type: type)
                return
            }
        }
        return nil
    }

    private init(data: Data, type: UTType) {
        self.data = data
        self.type = type
    }

    /// Whether the file is a PNG made from this TIFF (one that holds a single image), rather than
    /// the data as it is. Reads the header only.
    var convertsToPNG: Bool {
        guard type == .tiff, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) == 1
    }

    /// What goes into the file: a TIFF that holds a single image as PNG, which is what
    /// applications expect of an image file; anything else as it is. A TIFF with several pages,
    /// or one that cannot be decoded, stays a TIFF.
    var fileRepresentation: ImageRepresentation {
        let unfiltered = data.count >= RestoreMetrics.unfilteredPNGThreshold
        guard type == .tiff, let png = Self.pngData(fromSingleImageTIFF: data, unfiltered: unfiltered) else { return self }
        return ImageRepresentation(data: png, type: .png)
    }

    /// - Parameter unfiltered: Skip PNG's row filters: the same pixels in a larger file, encoded
    ///   in about half the time. For the largest images, whose copy is made while the paste
    ///   holds the main thread.
    static func pngData(fromSingleImageTIFF data: Data, unfiltered: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = unfiltered
            ? [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGCompressionFilter: RestoreMetrics.pngNoFilter]]
            : [:]
        // From the source rather than from a decoded image: that carries the metadata (resolution) over.
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
