import CoreGraphics
import Foundation

/// Contact sheets for reviewing the icon: every rendition at its real pixel size on a light and a
/// dark strip, plus the small ones enlarged without smoothing so each pixel can be judged.
enum Sheets {
    static let light = RGBA(0xF4F5F4)
    static let dark = RGBA(0x1F2120)

    /// One strip per row of images: each image is drawn at its pixel size, then the ones listed in
    /// `zoomed` again, enlarged `zoom` times with nearest-neighbour sampling.
    static func sizeSheet(rows: [[CGImage]], zoomIndices: [Int], zoom: Int = 4, padding: Int = 32) -> CGImage {
        // Lay out one row to measure it.
        func rowWidth(_ images: [CGImage]) -> Int {
            let plain = images.reduce(0) { $0 + $1.width + padding }
            let zoomedWidth = zoomIndices.filter { $0 < images.count }.reduce(0) { $0 + images[$1].width * zoom + padding }
            return padding + plain + zoomedWidth
        }
        func rowHeight(_ images: [CGImage]) -> Int {
            let tallest = images.map(\.height).max() ?? 0
            let tallestZoomed = zoomIndices.filter { $0 < images.count }.map { images[$0].height * zoom }.max() ?? 0
            return max(tallest, tallestZoomed) + 2 * padding
        }
        let width = rows.map(rowWidth).max() ?? 1
        let stripHeights = rows.map(rowHeight)
        let height = stripHeights.reduce(0, +) * 2
        let context = Rasterizer.makeContext(width: width, height: height)

        var top = 0
        for background in [light, dark] {
            for (index, images) in rows.enumerated() {
                let stripHeight = stripHeights[index]
                // Bitmap space is y-up.
                let stripBottom = height - top - stripHeight
                context.setFillColor(background.cgColor)
                context.fill(CGRect(x: 0, y: stripBottom, width: width, height: stripHeight))
                let baseline = stripBottom + padding
                var x = padding
                context.interpolationQuality = .high
                for image in images {
                    context.draw(image, in: CGRect(x: x, y: baseline + (stripHeight - 2 * padding - image.height) / 2,
                                                   width: image.width, height: image.height))
                    x += image.width + padding
                }
                context.interpolationQuality = .none
                for index in zoomIndices where index < images.count {
                    let image = images[index]
                    let w = image.width * zoom, h = image.height * zoom
                    context.draw(image, in: CGRect(x: x, y: baseline + (stripHeight - 2 * padding - h) / 2, width: w, height: h))
                    x += w + padding
                }
                top += stripHeight
            }
        }
        guard let image = context.makeImage() else { fatalError("Could not read back the sheet") }
        return image
    }

    /// Images side by side on one background, each scaled to `side` pixels.
    static func strip(_ images: [CGImage], side: Int, background: RGBA, padding: Int = 32, smoothing: Bool = true) -> CGImage {
        let width = padding + images.count * (side + padding)
        let height = side + 2 * padding
        let context = Rasterizer.makeContext(width: width, height: height)
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = smoothing ? .high : .none
        for (index, image) in images.enumerated() {
            context.draw(image, in: CGRect(x: padding + index * (side + padding), y: padding, width: side, height: side))
        }
        guard let image = context.makeImage() else { fatalError("Could not read back the strip") }
        return image
    }

    /// Stacks images vertically, left-aligned, on `background`.
    static func stack(_ images: [CGImage], background: RGBA) -> CGImage {
        let width = images.map(\.width).max() ?? 1
        let height = images.reduce(0) { $0 + $1.height }
        let context = Rasterizer.makeContext(width: width, height: height)
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var top = 0
        for image in images {
            context.draw(image, in: CGRect(x: 0, y: height - top - image.height, width: image.width, height: image.height))
            top += image.height
        }
        guard let image = context.makeImage() else { fatalError("Could not read back the stack") }
        return image
    }
}
