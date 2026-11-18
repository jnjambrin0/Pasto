import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Output {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw IconKitError("Could not create \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw IconKitError("Could not write \(url.path)") }
    }

    /// The same picture without an alpha channel (for backgrounds, which are never transparent).
    static func opaque(_ image: CGImage) -> CGImage {
        let context = Rasterizer.makeContext(width: image.width, height: image.height, opaque: true)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { fatalError("Could not flatten a \(image.width)×\(image.height) image") }
        return result
    }

    static func write(_ text: String, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func readPNG(_ url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw IconKitError("Could not read \(url.path)") }
        return image
    }
}

struct IconKitError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
