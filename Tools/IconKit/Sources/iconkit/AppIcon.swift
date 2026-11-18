import CoreGraphics
import Foundation

/// Pasto's app icon: the mark, two green leaves, on a white tile.
///
/// macOS icons sit on a 1024-unit grid: an 824-unit tile, centred, with a soft shadow below it in
/// the 100-unit margin. The tile has continuous corners with a radius of 214 units, measured on the
/// system's own icons on macOS 27 (rendered at 1024 px, their mask matches this shape to within the
/// anti-aliasing). Each size is drawn directly from the mark, never by scaling another rendition,
/// with the tile on whole pixels.
///
/// The tile is white at the top and a shade greyer at the bottom, enough for it to read as a
/// surface next to a white window. The mark takes more of the tile as the icon gets smaller, so
/// that at 16 pt the two leaves are still two leaves. It is not centred on its bounding box: the
/// leaves are broad at the foot and come to a point at the top, so their weight sits below the
/// middle of the box, and a mark centred by its box looks as if it had slipped down. It is moved
/// part of the way towards having its weight in the middle (`opticalShare`).
struct AppIcon {
    static let canvas: CGFloat = 1024
    static let tileSide: CGFloat = 824
    static let cornerRadius: CGFloat = 214
    static let shadowOffset: CGFloat = 10
    static let shadowBlur: CGFloat = 20
    static let shadowColor = RGBA(0x000000, alpha: 0.3)
    static let tileTop = RGBA(0xFFFFFF)
    static let tileBottom = RGBA(0xECF0E9)

    /// How much of the distance between the middle of the mark's box and its weight is corrected.
    static let opticalShare: CGFloat = 0.4

    let mark: Mark
    /// Where the mark's weight is, measured once.
    private let weight: CGVector

    init(mark: Mark) {
        self.mark = mark
        weight = mark.weightOffset
    }

    /// The mark's height as a share of the tile's side, for an icon `pixels` wide.
    static func markHeight(pixels: Int) -> CGFloat {
        switch pixels {
        case ...16: 0.80
        case ...32: 0.76
        case ...64: 0.72
        default: 0.68
        }
    }

    // MARK: Renditions

    /// The asset catalog's rendition for a point size and scale.
    func image(points: Int, scale: Int) -> CGImage {
        icon(pixels: points * scale)
    }

    /// The icon as macOS draws it: the tile on the 1024 grid, scaled to `pixels` with its edges on
    /// whole pixels, and its shadow.
    func icon(pixels: Int) -> CGImage {
        // 1 px of margin at 16 px and 3 px at 32 px, like the system's icons at those sizes.
        let inset = (CGFloat(pixels) * (Self.canvas - Self.tileSide) / 2 / Self.canvas).rounded(.down)
        let tile = CGRect(x: inset, y: inset, width: CGFloat(pixels) - 2 * inset, height: CGFloat(pixels) - 2 * inset)
        let unit = CGFloat(pixels) / Self.canvas
        let shape = tilePath(tile)
        let context = Rasterizer.makeContext(width: pixels, height: pixels)
        context.saveGState()
        // Bitmap space is y-up: the shadow falls below with a negative offset.
        context.setShadow(offset: CGSize(width: 0, height: -Self.shadowOffset * unit), blur: Self.shadowBlur * unit,
                          color: Self.shadowColor.cgColor)
        context.addPath(shape)
        context.setFillColor(RGBA.black.cgColor)
        context.fillPath()
        context.restoreGState()
        context.addPath(shape)
        context.clip()
        drawTile(tile, markHeight: Self.markHeight(pixels: pixels), in: context)
        return Self.snapshot(context)
    }

    /// The tile alone, filling the square: no margin, no shadow (favicons).
    func flatTile(pixels: Int) -> CGImage {
        let tile = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        let context = Rasterizer.makeContext(width: pixels, height: pixels)
        context.addPath(tilePath(tile))
        context.clip()
        drawTile(tile, markHeight: Self.markHeight(pixels: pixels), in: context)
        return Self.snapshot(context)
    }

    /// The tile as an opaque square, for platforms that apply their own mask. The mark is smaller
    /// than on the icon so that a circular mask leaves it whole.
    func square(pixels: Int) -> CGImage {
        let context = Rasterizer.makeContext(width: pixels, height: pixels, opaque: true)
        drawTile(CGRect(x: 0, y: 0, width: pixels, height: pixels), markHeight: 0.6, in: context)
        return Self.snapshot(context)
    }

    /// The mark alone on a transparent square, `margin` of the side clear on its longer dimension.
    func markAlone(pixels: Int, margin: CGFloat = 0.04) -> CGImage {
        let context = Rasterizer.makeContext(width: pixels, height: pixels)
        drawMark(in: CGRect(x: 0, y: 0, width: pixels, height: pixels), height: 1 - 2 * margin, context: context)
        return Self.snapshot(context)
    }

    func tilePath(_ tile: CGRect) -> CGPath {
        continuousRoundedRect(tile, radius: Self.cornerRadius * tile.width / Self.tileSide)
    }

    // MARK: Drawing

    /// Fills `tile` with the tile's surface and draws the mark on it. The caller clips to the shape.
    private func drawTile(_ tile: CGRect, markHeight: CGFloat, in context: CGContext) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: [Self.tileTop.cgColor, Self.tileBottom.cgColor] as CFArray, locations: [0, 1])
        else { fatalError("Invalid gradient") }
        // Bitmap space is y-up: the top of the tile is its maxY.
        context.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        drawMark(in: tile, height: markHeight, context: context)
    }

    /// Draws the mark in the middle of `rect`, `height` of the rectangle's side tall.
    private func drawMark(in rect: CGRect, height: CGFloat, context: CGContext) {
        let markHeight = rect.height * height
        let markWidth = markHeight * mark.aspect
        // Bitmap space is y-up and the weight is measured y-down: weight below the middle moves the
        // mark up.
        let target = CGRect(x: rect.midX - markWidth / 2 - Self.opticalShare * weight.dx * markWidth,
                            y: rect.midY - markHeight / 2 + Self.opticalShare * weight.dy * markHeight,
                            width: markWidth, height: markHeight)
        // Resampled to the pixels it covers, then placed: the last step is at most a half-pixel shift.
        let image = Self.resampled(mark.trimmed, width: max(1, Int(markWidth.rounded(.up))), height: max(1, Int(markHeight.rounded(.up))))
        context.draw(image, in: target)
    }

    /// `image` at `width` × `height`: halved with high-quality interpolation until it is within
    /// twice the target, then drawn at the target. One large step would skip most of the source's
    /// pixels and alias.
    static func resampled(_ image: CGImage, width: Int, height: Int) -> CGImage {
        var current = image
        while current.width / 2 >= width * 2, current.height / 2 >= height * 2 {
            let context = Rasterizer.makeContext(width: current.width / 2, height: current.height / 2)
            context.draw(current, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            current = snapshot(context)
        }
        let context = Rasterizer.makeContext(width: width, height: height)
        context.draw(current, in: CGRect(x: 0, y: 0, width: width, height: height))
        return snapshot(context)
    }

    private static func snapshot(_ context: CGContext) -> CGImage {
        guard let image = context.makeImage() else { fatalError("Could not read back a \(context.width)×\(context.height) bitmap") }
        return image
    }
}
