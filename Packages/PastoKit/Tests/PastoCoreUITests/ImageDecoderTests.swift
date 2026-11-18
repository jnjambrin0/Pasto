import CoreGraphics
import Foundation
import ImageIO
@testable import PastoCoreUI
import Testing
import UniformTypeIdentifiers

@Suite struct ImageDecoderTests {
    /// A small PNG.
    private static func png(side: Int = 8) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func aDecodedImageIsKeptUntilMemoryRunsShort() async throws {
        let decoder = ImageDecoder()
        let data = try Self.png()

        #expect(decoder.cachedImage(for: data) == nil)
        let image = try #require(await decoder.image(for: data))
        #expect(image.width == 8)
        #expect(decoder.cachedImage(for: data) != nil)

        // What the memory-pressure handler does.
        decoder.removeAllImages()
        #expect(decoder.cachedImage(for: data) == nil)
        #expect(await decoder.image(for: data) != nil)
    }

    @Test func theDefaultLimitHoldsSomeScreenfulsOfThumbnails() {
        // A card thumbnail is at most 560 × 460 px, 4 bytes a pixel.
        let thumbnail = 560 * 460 * 4
        #expect(ImageDecoder.defaultByteLimit / thumbnail >= 8 * 8)
        #expect(ImageDecoder.defaultByteLimit <= 64 * 1024 * 1024)
    }
}
