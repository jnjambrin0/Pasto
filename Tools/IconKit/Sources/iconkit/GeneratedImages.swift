import CoreGraphics
import Foundation
import ImageIO

/// Brings the source illustrations (`Design/generated/`) into the app and the DMG: checks them,
/// crops them to the part every screen shows and writes the scales the app loads.
/// `scripts/import-illustrations.sh` drives it.
///
/// Illustrations are drawn on a 3:2 canvas (1536 × 1024) with everything that matters inside a
/// centred safe area of 1280 × 800 (8:5). The app shows them at 8:5 too: the crop keeps the whole
/// width and 960 of the 1024 rows, which always contains the safe area. Where a picture runs off its
/// bottom edge (grass, a panel rising from below), the crop keeps that edge and drops rows at the
/// top instead (`Crop.bottom`).
enum GeneratedImages {
    static let canvasAspect: CGFloat = 1536.0 / 1024.0
    static let minimumCanvasWidth = 1536
    /// The proportion every screen shows: the safe area's.
    static let displayAspect: CGFloat = 1280.0 / 800.0

    enum Crop: String {
        /// Rows dropped evenly from the top and the bottom.
        case center
        /// The bottom edge kept: rows dropped from the top only.
        case bottom
    }

    /// Reads a generated picture and returns it as an opaque sRGB image, or explains why it cannot
    /// be used.
    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw IconKitError("\(url.lastPathComponent) is not a readable image") }
        let opaque = try flattened(image, name: url.lastPathComponent)
        return opaque
    }

    /// Draws the image into an opaque sRGB bitmap. An alpha channel is accepted only when every pixel
    /// is fully opaque: a transparent area would show the window through the picture.
    static func flattened(_ image: CGImage, name: String) throws -> CGImage {
        let width = image.width, height = image.height
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let context = Rasterizer.makeContext(width: width, height: height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        if hasAlpha, let data = context.data {
            let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
            var transparent = 0
            for y in 0..<height {
                for x in 0..<width where pixels[y * context.bytesPerRow + x * 4 + 3] < 255 {
                    transparent += 1
                }
            }
            if transparent > 0 {
                throw IconKitError("\(name) has \(transparent) pixels that are not fully opaque: export it without transparency")
            }
        }
        guard let result = context.makeImage() else { throw IconKitError("could not convert \(name)") }
        return result
    }

    /// Checks the canvas of an onboarding illustration and returns the 8:5 part the app shows.
    static func displayCrop(of image: CGImage, name: String, crop: Crop) throws -> CGImage {
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        guard abs(aspect - canvasAspect) / canvasAspect < 0.01 else {
            throw IconKitError("\(name) is \(image.width) × \(image.height); it must be 3:2 (1536 × 1024)")
        }
        guard image.width >= minimumCanvasWidth else {
            throw IconKitError("\(name) is \(image.width) px wide; at least \(minimumCanvasWidth) px are needed for the @3x scale")
        }
        return try cropRows(image, name: name, aspect: displayAspect, crop: crop)
    }

    /// The full width of `image` and as many rows as `aspect` allows, taken from the middle or from
    /// the bottom. Bitmap rows count from the top.
    static func cropRows(_ image: CGImage, name: String, aspect: CGFloat, crop: Crop) throws -> CGImage {
        let height = min((CGFloat(image.width) / aspect).rounded(), CGFloat(image.height))
        let width = min(CGFloat(image.width), (height * aspect).rounded())
        let spare = CGFloat(image.height) - height
        let top = crop == .bottom ? spare : (spare / 2).rounded()
        let rect = CGRect(x: ((CGFloat(image.width) - width) / 2).rounded(), y: top, width: width, height: height)
        guard let cropped = image.cropping(to: rect) else { throw IconKitError("could not crop \(name)") }
        return cropped
    }

    /// Writes `<name>.png`, `@2x` and `@3x` for a picture shown at `points`.
    static func writeScales(_ image: CGImage, points: CGSize, name: String, to folder: URL) throws {
        for scale in 1...3 {
            let width = Int(points.width) * scale, height = Int(points.height) * scale
            let context = Rasterizer.makeContext(width: width, height: height, opaque: true)
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { throw IconKitError("could not scale \(name)") }
            let file = scale == 1 ? "\(name).png" : "\(name)@\(scale)x.png"
            try Output.writePNG(scaled, to: folder.appendingPathComponent(file))
        }
    }

    /// The DMG texture: a landscape picture cropped to the window's 660 × 400 proportion, keeping
    /// its bottom edge (where its grass is), and stored at @2x.
    static func importTexture(_ url: URL, to output: URL) throws {
        let image = try load(url)
        guard image.width >= Int(DMGBackground.size.width) * 2, image.width > image.height else {
            throw IconKitError("\(url.lastPathComponent) is \(image.width) × \(image.height); the DMG background needs a landscape picture at least 1320 px wide")
        }
        let cropped = try cropRows(image, name: url.lastPathComponent,
                                   aspect: DMGBackground.size.width / DMGBackground.size.height, crop: .bottom)
        let pixelWidth = Int(DMGBackground.size.width) * 2, pixelHeight = Int(DMGBackground.size.height) * 2
        let context = Rasterizer.makeContext(width: pixelWidth, height: pixelHeight, opaque: true)
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard let opaque = context.makeImage() else { throw IconKitError("could not convert the texture") }
        try Output.writePNG(opaque, to: output)
    }
}
