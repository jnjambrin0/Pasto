import AppKit
import CoreGraphics
import Foundation

/// The menu bar glyph: the app's tile, filled, with a large leaf cut out of it and a smaller one
/// beside it. A template image (only alpha matters; AppKit tints it), 18 × 18 pt, @1x and @2x.
///
/// The geometry is in points with y up, the way the glyph was first drawn. Its pixel rules:
///
/// - The tile is 14 × 14 pt at (2, 2), so its straight edges sit on whole pixels at 1x and 2x and stay
///   crisp; its corners are the app icon's (continuous, 26 % of the side). 14 pt is the size of the
///   filled squares SF Symbols draw at 15 pt medium, such as `app.fill`.
/// - The leaves stand on y = 4, a whole pixel at both scales: a 2 pt band of tile below them reads as
///   the ground they grow from.
/// - At 1x every row and column has at least one fully solid pixel between two holes and between a
///   hole and the tile's edge, so no hairline of half-covered pixels is left; `hairlines(in:)`
///   checks it, and `status-item` refuses to write a glyph that fails.
enum StatusGlyph {
    static let points = 18

    /// A leaf in negative space: a flat base and a pointed tip, its outer edge swelling outwards.
    struct Leaf {
        /// Centre of the flat base.
        var base: CGPoint
        var tip: CGPoint
        /// Width of the base.
        var width: CGFloat
        /// How far the outer (upper left) edge swells, in base widths.
        var outerSwell: CGFloat
        /// How far the inner (lower right) edge swells, in base widths.
        var innerSwell: CGFloat

        func add(to path: CGMutablePath) {
            let height = tip.y - base.y, lean = tip.x - base.x
            path.move(to: CGPoint(x: base.x - width / 2, y: base.y))
            path.addCurve(to: tip,
                          control1: CGPoint(x: base.x - width * outerSwell - lean * 0.1, y: base.y + height * 0.45),
                          control2: CGPoint(x: tip.x - width * 0.35, y: tip.y - height * 0.25))
            path.addCurve(to: CGPoint(x: base.x + width / 2, y: base.y),
                          control1: CGPoint(x: tip.x + width * 0.1, y: tip.y - height * 0.45),
                          control2: CGPoint(x: base.x + width * innerSwell, y: base.y + height * 0.3))
            path.closeSubpath()
        }
    }

    static let tile = CGRect(x: 2, y: 2, width: 14, height: 14)
    static var tileRadius: CGFloat { AppIcon.cornerRadius * tile.width / AppIcon.tileSide }
    static let leaves = [
        Leaf(base: CGPoint(x: 6.5, y: 4), tip: CGPoint(x: 12, y: 14.2), width: 4, outerSwell: 1, innerSwell: 0.5),
        Leaf(base: CGPoint(x: 11.75, y: 4), tip: CGPoint(x: 14, y: 9.6), width: 2.5, outerSwell: 0.35, innerSwell: 0.55),
    ]

    /// The tile with the leaves as holes (even-odd), in the scene's y-down space.
    static var path: CGPath {
        let path = CGMutablePath()
        path.addPath(continuousRoundedRect(tile, radius: tileRadius))
        for leaf in leaves { leaf.add(to: path) }
        return path.transformed(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(points)))
    }

    static func render(scale: Int) -> CGImage {
        let scene = Scene(side: CGFloat(points), layers: [
            Layer(name: "glyph", items: [Item(path: path, paint: .solid(.black), fillRule: .evenOdd)]),
        ])
        return Rasterizer.render(scene, pixels: points * scale)
    }

    // MARK: Checks

    /// Runs of ink with a hole on at least one side and no fully solid pixel: hairlines, along every
    /// row and column. A hole is a pixel under half coverage with ink further along the same line.
    static func hairlines(in image: CGImage) -> [String] {
        let coverage = alpha(of: image)
        let side = coverage.count
        var found: [String] = []
        func scan(_ line: [Double], _ label: String) {
            var start = 0
            while start < side {
                guard line[start] >= 0.5 else { start += 1; continue }
                var end = start
                while end < side, line[end] >= 0.5 { end += 1 }
                let holeBefore = start > 0 && line[..<start].contains { $0 >= 0.5 }
                let holeAfter = end < side && line[end...].contains { $0 >= 0.5 }
                let solidest = line[start..<end].max() ?? 0
                if holeBefore || holeAfter, solidest < 0.95 {
                    found.append("\(label), pixels \(start)–\(end - 1): \(Int(solidest * 100)) % at most")
                }
                start = end
            }
        }
        for row in 0..<side { scan(coverage[row], "row \(row) from the top") }
        for column in 0..<side { scan(coverage.map { $0[column] }, "column \(column)") }
        return found
    }

    /// Alpha of every pixel, 0…1, rows from the top.
    static func alpha(of image: CGImage) -> [[Double]] {
        let width = image.width, height = image.height
        let context = Rasterizer.makeContext(width: width, height: height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return [] }
        let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        return (0..<height).map { y in (0..<width).map { x in Double(pixels[y * context.bytesPerRow + x * 4 + 3]) / 255 } }
    }

    // MARK: Review sheet

    /// The symbols the glyph sits among in the menu bar, at the configuration it is matched to.
    static let neighbours = ["wifi", "battery.75percent", "magnifyingglass", "clock"]
    static var neighbourConfiguration: NSImage.SymbolConfiguration { NSImage.SymbolConfiguration(pointSize: 15, weight: .medium) }

    /// The glyph on a light and a dark menu bar beside SF Symbols, at 1x and 2x; both scales enlarged
    /// without smoothing; its dimmed states and the symbol that replaces it while paused; and the
    /// Stack panel's title, which shows it too.
    static func sheet() -> CGImage {
        let bars: [(background: RGBA, ink: RGBA, panel: RGBA)] = [
            (RGBA(0xE9E9EA), RGBA(0x000000, alpha: 0.85), RGBA(0xF4F6F4)),
            (RGBA(0x2A2A2C), RGBA(0xFFFFFF), RGBA(0x2F3E35)),
        ]
        let glyphs = [render(scale: 1), render(scale: 2)]
        let padding = 24, zoom1 = 8, zoom2 = 4
        let stripHeight = points * zoom1 + 2 * padding
        let width = 1460
        var strips: [CGImage] = []
        for bar in bars {
            let context = Rasterizer.makeContext(width: width, height: stripHeight)
            context.setFillColor(bar.background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: stripHeight))
            let middle = stripHeight / 2
            var x = padding
            func place(_ image: CGImage, smoothing: Bool = false, scale: Int = 1) {
                context.interpolationQuality = smoothing ? .high : .none
                let w = image.width * scale, h = image.height * scale
                context.draw(image, in: CGRect(x: x, y: middle - h / 2, width: w, height: h))
                x += w
            }
            // The menu bar at 1x, then at 2x: the neighbours, then the glyph.
            for scale in [1, 2] {
                for name in neighbours {
                    place(tinted(symbol(name, scale: scale), bar.ink))
                    x += 8 * scale
                }
                place(tinted(glyphs[scale - 1], bar.ink))
                x += padding
            }
            // Each scale enlarged, pixel by pixel.
            place(tinted(glyphs[0], bar.ink), scale: zoom1)
            x += padding / 2
            place(tinted(glyphs[1], bar.ink), scale: zoom2)
            x += padding
            // States at 2x: the capture pulse (35 %), capture blocked (AppKit draws a disabled
            // template at half its opacity), paused (the glyph gives way to `pause.circle`).
            for opacity in [0.35, 0.5] {
                place(tinted(glyphs[1], bar.ink.opacity(bar.ink.alpha * opacity)))
                x += 16
            }
            place(tinted(bitmap(of: pausedSymbol, scale: 2), bar.ink))
            x += padding
            // The Stack panel's title at 2x: the glyph at its own size, framed to the 14 pt tile.
            let header = CGRect(x: x, y: middle - 44, width: 260, height: 88)
            context.setFillColor(bar.panel.cgColor)
            context.addPath(roundedRect(header, radius: 24))
            context.fillPath()
            x += 24
            place(tinted(glyphs[1], bar.ink))
            x += 2 * (8 - (points - Int(tile.width)) / 2)
            drawTitle("Stack", in: context, at: CGPoint(x: x, y: middle), color: bar.ink.opacity(1))
            let used = Int(header.maxX) + padding
            guard let strip = snapshot(context).cropping(to: CGRect(x: 0, y: 0, width: used, height: stripHeight)) else {
                fatalError("Could not crop the glyph sheet")
            }
            strips.append(strip)
        }
        return Sheets.stack(strips, background: .white)
    }

    static var pausedSymbol: NSImage {
        guard let image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil) else {
            fatalError("No pause.circle symbol")
        }
        return image
    }

    private static func symbol(_ name: String, scale: Int) -> CGImage {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(neighbourConfiguration)
        else { fatalError("No \(name) symbol") }
        return bitmap(of: image, scale: scale)
    }

    /// `image` drawn into a bitmap of `scale` pixels per point.
    private static func bitmap(of image: NSImage, scale: Int) -> CGImage {
        let width = Int((image.size.width * CGFloat(scale)).rounded(.up)), height = Int((image.size.height * CGFloat(scale)).rounded(.up))
        let context = Rasterizer.makeContext(width: width, height: height)
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return snapshot(context)
    }

    /// The panel title's font (title 3, medium) at 2x, its baseline set so the text centres on `point`.
    private static func drawTitle(_ text: String, in context: CGContext, at point: CGPoint, color: RGBA) {
        let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize * 2, weight: .medium)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color.cgColor) ?? .black])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: NSPoint(x: point.x, y: point.y - (font.ascender + font.descender) / 2))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Recolours a template image the way AppKit does: the colour, masked by the image's alpha.
    private static func tinted(_ image: CGImage, _ color: RGBA) -> CGImage {
        let context = Rasterizer.makeContext(width: image.width, height: image.height)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)
        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        return snapshot(context)
    }

    private static func snapshot(_ context: CGContext) -> CGImage {
        guard let image = context.makeImage() else { fatalError("Could not read back the glyph sheet") }
        return image
    }
}
