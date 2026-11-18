import CoreGraphics
import Foundation
import ImageIO
import PastoCore

extension PasteboardItemSnapshot {
    /// An item with these representations, in this order.
    init(_ representations: KeyValuePairs<String, Data>) {
        self.init(
            types: representations.map(\.key),
            dataByType: Dictionary(representations.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// An item whose representations are the UTF-8 bytes of these strings, in this order.
    init(strings: KeyValuePairs<String, String>) {
        self.init(
            types: strings.map(\.key),
            dataByType: Dictionary(strings.map { ($0.key, Data($0.value.utf8)) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// What copying `string` as plain text puts on the pasteboard.
    static func text(_ string: String) -> PasteboardItemSnapshot {
        PasteboardItemSnapshot(["public.utf8-plain-text": Data(string.utf8)])
    }

    /// A file copied in Finder.
    static func file(_ path: String) -> PasteboardItemSnapshot {
        PasteboardItemSnapshot(["public.file-url": Data(URL(filePath: path).absoluteString.utf8)])
    }
}

/// Images made of pixels the tests choose.
enum TestImage {
    struct Pixel {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8 = 255

        static let red = Pixel(red: 255, green: 0, blue: 0)
        static let clear = Pixel(red: 0, green: 0, blue: 0, alpha: 0)
    }

    /// An image whose pixel at (`x`, `y`) — `y` counted from the top — is `pixel(x, y)`.
    /// With `hasAlpha` false the image has no alpha channel at all.
    static func make(width: Int, height: Int, hasAlpha: Bool = true, pixel: (Int, Int) -> Pixel) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                let offset = (y * width + x) * 4
                // Premultiplied, as the bitmap declares.
                bytes[offset] = UInt8(Int(value.red) * Int(value.alpha) / 255)
                bytes[offset + 1] = UInt8(Int(value.green) * Int(value.alpha) / 255)
                bytes[offset + 2] = UInt8(Int(value.blue) * Int(value.alpha) / 255)
                bytes[offset + 3] = value.alpha
            }
        }
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    static func solid(_ pixel: Pixel, width: Int, height: Int, hasAlpha: Bool = true) -> CGImage {
        make(width: width, height: height, hasAlpha: hasAlpha) { _, _ in pixel }
    }

    /// `image` as a file of the given type would hold it, declaring a resolution if given one.
    static func encoded(_ image: CGImage, as type: String = "public.png", dotsPerInch: Double? = nil) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
        let properties = dotsPerInch.map { [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The pixel size of encoded image data.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return CGSize(width: image.width, height: image.height)
    }
}
