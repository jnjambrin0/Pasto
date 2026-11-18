import CoreGraphics
import Foundation
import ImageIO

/// Pasto's app icon, made from one painted artwork: `Design/icon/source/app-icon-artwork.png`, a
/// full-bleed square with no rounded corners (three frosted clipboard cards rising from the grass
/// on a green field). Every rendition in the repository comes from that file and nothing else.
///
/// macOS icons sit on a 1024-unit grid: an 824-unit tile, centred, with a soft shadow below it in
/// the 100-unit margin. The tile has continuous corners with a radius of 214 units, measured on the
/// system's own icons on macOS 27 (rendered at 1024 px, their mask matches this shape to within the
/// anti-aliasing). Each size is drawn directly from the artwork, never by scaling another
/// rendition, with the tile on whole pixels.
///
/// At 16 pt the whole picture is too small to read: its cards turn into a pale smudge. Those sizes
/// show a crop of the artwork centred on the front card and the grass instead (`tightCrop`), and the
/// 32 pt @1x rendition a looser one that keeps the stack of cards (`stackCrop`); 64 px and up show the
/// whole artwork.
struct AppIcon {
    static let canvas: CGFloat = 1024
    static let tileSide: CGFloat = 824
    static let cornerRadius: CGFloat = 214
    static let shadowOffset: CGFloat = 10
    static let shadowBlur: CGFloat = 20
    static let shadowColor = RGBA(0x000000, alpha: 0.3)

    /// Parts of the artwork, as fractions of its side, measured from its top-left corner.
    static let tightCrop = CGRect(x: 0.25, y: 0.25, width: 0.62, height: 0.62)
    static let stackCrop = CGRect(x: 0.20, y: 0.22, width: 0.70, height: 0.70)

    let artwork: CGImage

    init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw IconKitError("cannot read the icon artwork at \(url.path)") }
        guard image.width == image.height, image.width >= Int(Self.canvas) else {
            throw IconKitError("\(url.lastPathComponent) is \(image.width) × \(image.height); the icon artwork must be square, 1024 px or larger")
        }
        artwork = try GeneratedImages.flattened(image, name: url.lastPathComponent)
    }

    /// The part of the artwork a rendition shows, or all of it.
    func content(_ crop: CGRect?) -> CGImage {
        guard let crop else { return artwork }
        let side = CGFloat(artwork.width)
        let rect = CGRect(x: crop.minX * side, y: crop.minY * side, width: crop.width * side, height: crop.height * side).integral
        guard let cropped = artwork.cropping(to: rect) else { fatalError("The crop \(crop) falls outside the artwork") }
        return cropped
    }

    // MARK: Renditions

    /// The asset catalog's rendition for a point size and scale.
    func image(points: Int, scale: Int) -> CGImage {
        let crop: CGRect? = switch (points, scale) {
        case (16, _): Self.tightCrop
        case (32, 1): Self.stackCrop
        default: nil
        }
        return icon(pixels: points * scale, crop: crop)
    }

    /// The icon as macOS draws it: the tile on the 1024 grid, scaled to `pixels` with its edges on
    /// whole pixels, and its shadow.
    func icon(pixels: Int, crop: CGRect? = nil) -> CGImage {
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
        context.draw(Self.resampled(content(crop), width: Int(tile.width), height: Int(tile.height)), in: tile)
        return Self.snapshot(context)
    }

    /// The tile alone, filling the square: no margin, no shadow (favicons).
    func flatTile(pixels: Int, crop: CGRect? = nil) -> CGImage {
        let tile = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        let context = Rasterizer.makeContext(width: pixels, height: pixels)
        context.addPath(tilePath(tile))
        context.clip()
        context.draw(Self.resampled(content(crop), width: pixels, height: pixels), in: tile)
        return Self.snapshot(context)
    }

    /// The whole artwork as an opaque square, for platforms that apply their own mask.
    func square(pixels: Int) -> CGImage {
        let context = Rasterizer.makeContext(width: pixels, height: pixels, opaque: true)
        context.draw(Self.resampled(artwork, width: pixels, height: pixels), in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return Self.snapshot(context)
    }

    func tilePath(_ tile: CGRect) -> CGPath {
        continuousRoundedRect(tile, radius: Self.cornerRadius * tile.width / Self.tileSide)
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
