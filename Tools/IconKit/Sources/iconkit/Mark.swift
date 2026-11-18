import CoreGraphics
import Foundation
import ImageIO

/// Pasto's mark, two leaves, lifted off the logo in `Design/icon/source/logo.png`.
///
/// The logo is the mark painted on a plain white square. Everything IconKit draws needs the mark
/// alone, so that it can sit on the icon's tile at any size, on a transparent favicon or on a dark
/// page. Subtracting the white is not enough: the one or two pixels along each edge are a blend of
/// leaf and background, and would keep a pale fringe on anything darker than white. Each of those
/// pixels is split instead into the colour of the leaf next to it and the share of it that shows
/// (`coverage`), which is what an alpha channel means.
struct Mark {
    /// The mark alone on a transparent canvas of the logo's size.
    let image: CGImage
    /// How much of each pixel the mark covers, 0…1, row by row from the top.
    let coverage: [Float]
    let width: Int
    let height: Int
    /// The mark's bounding box in the logo, in pixels from its top-left corner.
    let bounds: CGRect

    /// A pixel this far from the background, on a 0…255 scale, is leaf all the way through.
    private static let solidDistance: Float = 150
    /// A pixel closer to the background than this is background (the logo's white is not quite even).
    private static let backgroundDistance: Float = 6
    /// How far an edge pixel looks for the leaf it belongs to.
    private static let reach = 3

    init(contentsOf url: URL) throws {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let logo = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw IconKitError("cannot read the logo at \(url.path)") }
        guard logo.width == logo.height, logo.width >= 1024 else {
            throw IconKitError("\(name) is \(logo.width) × \(logo.height); the logo must be square, 1024 px or larger")
        }
        let opaque = try GeneratedImages.flattened(logo, name: name)
        let width = opaque.width, height = opaque.height
        let context = Rasterizer.makeContext(width: width, height: height)
        context.draw(opaque, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { throw IconKitError("could not read the pixels of \(name)") }
        let stride = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: stride * height)
        func colour(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let offset = y * stride + x * 4
            return SIMD3(Float(pixels[offset]), Float(pixels[offset + 1]), Float(pixels[offset + 2]))
        }

        // The background is whatever the border is, and the border has to be plain and light.
        var border: [SIMD3<Float>] = []
        for index in 0..<width {
            border += [colour(index, 0), colour(index, height - 1), colour(0, index), colour(width - 1, index)]
        }
        let background = border.reduce(SIMD3<Float>(repeating: 0), +) / Float(border.count)
        let unevenness = border.map { ($0 - background).max() - ($0 - background).min() }.max() ?? 0
        guard background.min() > 240, unevenness < 2 * Self.backgroundDistance else {
            throw IconKitError("\(name) must be the mark on a plain white background that reaches every edge")
        }

        // How far each pixel is from the background: its darkest channel, since the leaves are green.
        var distance = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                distance[y * width + x] = (background - colour(x, y)).max()
            }
        }

        var coverage = [Float](repeating: 0, count: width * height)
        var output = [UInt8](repeating: 0, count: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let own = distance[index]
                guard own > Self.backgroundDistance else { continue }
                var leaf = colour(x, y)
                var alpha: Float = 1
                if own < Self.solidDistance {
                    // An edge pixel: the nearest solid pixel says what the leaf's colour is here, and
                    // how far this pixel is along the way from background to that colour is its coverage.
                    var best: (gap: Int, colour: SIMD3<Float>)?
                    for dy in -Self.reach...Self.reach {
                        for dx in -Self.reach...Self.reach {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height,
                                  distance[ny * width + nx] >= Self.solidDistance else { continue }
                            let gap = dx * dx + dy * dy
                            if best == nil || gap < best!.gap { best = (gap, colour(nx, ny)) }
                        }
                    }
                    if let best {
                        let whole = background - best.colour
                        alpha = ((background - leaf) * whole).sum() / (whole * whole).sum()
                        leaf = best.colour
                    } else {
                        // A speck with no leaf near it: take it for what it is.
                        alpha = own / Self.solidDistance
                        leaf = background - (background - leaf) / alpha
                    }
                    alpha = min(max(alpha, 0), 1)
                }
                guard alpha > 0.004 else { continue }
                coverage[index] = alpha
                let premultiplied = pointwiseMin(pointwiseMax(leaf, SIMD3(repeating: 0)), SIMD3(repeating: 255)) * alpha
                output[index * 4] = UInt8(premultiplied.x.rounded())
                output[index * 4 + 1] = UInt8(premultiplied.y.rounded())
                output[index * 4 + 2] = UInt8(premultiplied.z.rounded())
                output[index * 4 + 3] = UInt8((alpha * 255).rounded())
                if alpha > 0.05 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX > minX, maxY > minY else { throw IconKitError("\(name) is blank") }

        let result = Rasterizer.makeContext(width: width, height: height)
        guard let target = result.data else { throw IconKitError("could not write the mark") }
        let resultStride = result.bytesPerRow
        output.withUnsafeBytes { bytes in
            for y in 0..<height {
                memcpy(target + y * resultStride, bytes.baseAddress! + y * width * 4, width * 4)
            }
        }
        guard let image = result.makeImage() else { throw IconKitError("could not write the mark") }
        self.image = image
        self.coverage = coverage
        self.width = width
        self.height = height
        bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The mark cropped to its bounding box.
    var trimmed: CGImage {
        guard let cropped = image.cropping(to: bounds) else { fatalError("The mark's bounds fall outside the logo") }
        return cropped
    }

    /// Width over height of the mark's bounding box.
    var aspect: CGFloat { bounds.width / bounds.height }
}

extension Mark {
    /// Where the mark's weight is: the mean position of its pixels, as a share of its bounding box
    /// from the box's centre (x to the right, y down).
    var weightOffset: CGVector {
        var sumX = 0.0, sumY = 0.0, total = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let share = Double(coverage[y * width + x])
                guard share > 0 else { continue }
                sumX += share * Double(x); sumY += share * Double(y); total += share
            }
        }
        return CGVector(dx: (sumX / total - bounds.midX) / bounds.width, dy: (sumY / total - bounds.midY) / bounds.height)
    }
}
