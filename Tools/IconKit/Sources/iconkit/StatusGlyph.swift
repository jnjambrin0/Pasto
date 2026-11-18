import CoreGraphics
import Foundation

/// The menu-bar glyph: the icon reduced to its motif, one clipboard card with a sprout of grass
/// growing inside it. A template image (only alpha matters; AppKit tints it), 18 × 18 pt like the
/// glyph it replaces, so `PastoStatusItem` keeps its layout.
///
/// Each scale is drawn on its own pixel grid instead of scaling one drawing: the card outline is a
/// filled ring (outer shape minus inner shape) whose edges all sit on whole pixels, so it is crisp
/// on non-Retina screens too. The stroke is 1.5 pt at @2x, like SF Symbols in the menu bar, and a
/// whole pixel at @1x.
enum StatusGlyph {
    static let points = 18

    struct Spec {
        var scale: Int
        /// Outer edge of the card, in pixels.
        var card: CGRect
        var stroke: CGFloat
        var radius: CGFloat
        /// One "text" line near the top of the card, in pixels.
        var line: CGRect
        /// Rooted on the inner bottom edge, in pixels.
        var blades: [Blade]
    }

    /// The tuft leans right, like the breeze in the app icon's grass.
    static let specs = [
        Spec(scale: 1,
             card: CGRect(x: 3, y: 2, width: 12, height: 14), stroke: 1, radius: 3,
             line: CGRect(x: 6, y: 5, width: 5, height: 1),
             // Two blades, not three: at one pixel per point a third one closes the gaps.
             blades: [
                 Blade(7, width: 3, height: 7, lean: 2, stiffness: 0.5),
                 Blade(11, width: 3, height: 5, lean: 1.5, stiffness: 0.5),
             ]),
        Spec(scale: 2,
             card: CGRect(x: 6, y: 4, width: 24, height: 28), stroke: 3, radius: 6.5,
             line: CGRect(x: 12, y: 10, width: 9, height: 2),
             blades: [
                 Blade(13, width: 4.5, height: 11, lean: 3, stiffness: 0.5),
                 Blade(18, width: 5, height: 15, lean: 4.5, stiffness: 0.5),
                 Blade(23, width: 4, height: 9, lean: 3, stiffness: 0.5),
             ]),
    ]

    static func scene(_ spec: Spec) -> Scene {
        let ink = Paint.solid(.black)
        let inner = spec.card.insetBy(dx: spec.stroke, dy: spec.stroke)
        let ring = CGMutablePath()
        ring.addPath(roundedRect(spec.card, radius: spec.radius))
        ring.addPath(roundedRect(inner, radius: max(spec.radius - spec.stroke, 0.5)))
        var items = [Item(path: ring, paint: ink, fillRule: .evenOdd)]
        items.append(Item(path: roundedRect(spec.line, radius: spec.line.height / 2), paint: ink))
        // Rooted a hair inside the bottom stroke so blades and outline fuse without a seam.
        let baseY = inner.maxY + spec.stroke / 2
        for blade in spec.blades {
            items.append(Item(path: bladePath(blade, baseY: baseY), paint: ink))
        }
        let side = CGFloat(points * spec.scale)
        return Scene(side: side, layers: [Layer(name: "glyph", items: items)])
    }

    static func render(scale: Int) -> CGImage {
        guard let spec = specs.first(where: { $0.scale == scale }) else { fatalError("No glyph for @\(scale)x") }
        return Rasterizer.render(scene(spec), pixels: points * scale)
    }

    /// The glyph tinted for a light and a dark menu bar, at real size and enlarged.
    static func sheet() -> CGImage {
        let bars: [(background: RGBA, ink: RGBA)] = [(RGBA(0xE9E9EA), RGBA(0x000000, alpha: 0.85)), (RGBA(0x2A2A2C), RGBA(0xFFFFFF))]
        var strips: [CGImage] = []
        for bar in bars {
            let images = [1, 2].map { tinted(render(scale: $0), bar.ink) }
            // Real size (the @2x one at 36 px), then both enlarged to 144 px without smoothing.
            let width = 24 + 18 + 24 + 36 + 24 + 144 + 24 + 144 + 24
            let height = 144 + 48
            let context = Rasterizer.makeContext(width: width, height: height)
            context.setFillColor(bar.background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(images[0], in: CGRect(x: 24, y: (height - 18) / 2, width: 18, height: 18))
            context.draw(images[1], in: CGRect(x: 66, y: (height - 36) / 2, width: 36, height: 36))
            context.interpolationQuality = .none
            context.draw(images[0], in: CGRect(x: 126, y: 24, width: 144, height: 144))
            context.draw(images[1], in: CGRect(x: 294, y: 24, width: 144, height: 144))
            guard let strip = context.makeImage() else { fatalError("Could not read back the glyph sheet") }
            strips.append(strip)
        }
        return Sheets.stack(strips, background: .white)
    }

    /// Recolours a template image the way AppKit does: the colour, masked by the image's alpha.
    private static func tinted(_ image: CGImage, _ color: RGBA) -> CGImage {
        let context = Rasterizer.makeContext(width: image.width, height: image.height)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)
        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        guard let result = context.makeImage() else { fatalError("Could not tint the glyph") }
        return result
    }
}
