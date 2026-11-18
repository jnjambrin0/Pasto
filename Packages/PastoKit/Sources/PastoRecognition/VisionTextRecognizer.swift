import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Text recognition with Vision.
public struct VisionTextRecognizer: TextRecognizer {
    /// The longest side an image is recognized at; larger ones are reduced first.
    static let defaultMaxPixelSize = 1024
    /// An image with a side shorter than this is not looked at.
    static let minimumSide = 11

    private let maxPixelSize: Int

    public init() {
        maxPixelSize = Self.defaultMaxPixelSize
    }

    @concurrent
    public func recognizeWords(in imageData: Data) async throws -> [String] {
        guard !imageData.isEmpty else { throw TextRecognitionError.invalidImageData }
        let (image, orientation) = try Self.preparedImage(from: imageData, maxPixelSize: maxPixelSize)

        // Level, languages and revision are left as Vision sets them.
        var request = RecognizeTextRequest()
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image, orientation: orientation)
        return observations.flatMap { observation in
            observation.topCandidates(1).first.map { RecognizedText.words(in: $0.string) } ?? []
        }
    }

    /// Decodes the image, reduced to `maxPixelSize` when it is larger, and tells which way up it is.
    static func preparedImage(from data: Data, maxPixelSize: Int) throws -> (CGImage, CGImagePropertyOrientation) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw TextRecognitionError.noImageSource
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw TextRecognitionError.noImageProperties }
        guard min(width, height) >= minimumSide else { throw TextRecognitionError.imageTooSmall }

        guard max(width, height) > maxPixelSize else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw TextRecognitionError.imageDecodeFailed
            }
            let orientation = (properties[kCGImagePropertyOrientation] as? UInt32)
                .flatMap(CGImagePropertyOrientation.init) ?? .up
            return (image, orientation)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // The thumbnail comes out upright, so there is no orientation left to apply.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TextRecognitionError.thumbnailFailed
        }
        return (thumbnail, .up)
    }
}
