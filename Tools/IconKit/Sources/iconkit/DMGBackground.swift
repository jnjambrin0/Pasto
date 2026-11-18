import AppKit
import CoreGraphics
import Foundation

/// Background of the DMG window: 660 × 400 pt, an arrow from the app's slot to the Applications
/// slot, no text (it works in any language).
///
/// Seen in Finder on macOS 27.2 with the system in dark mode: over a background picture the icon
/// labels are drawn black, so over the nearly white texture they need no plate behind them (an
/// earlier version drew one, which Finder's black text sat badly on). The older note follows.
/// Finder draws the icon labels black in light mode and white in dark mode, and never adapts the
/// picture, so whatever is behind a label must carry both colours: a mid tone, about 4.5:1 with each
/// (`dmg-inspect` measures it on the real DMG).
///
/// - With the generated texture (`Config/dmg-texture.png`, imported by
///   `scripts/import-illustrations.sh`): the texture as it is, its grass along the bottom edge, plus
///   the arrow and a mid-tone plate under each label, since the texture is nearly white there.
/// - Without it, the vector meadow: a pale sky over a meadow whose crest the icons stand on, as
///   Pasto's cards rise from the grass; the labels fall on the meadow, which has that mid tone.
enum DMGBackground {
    static let size = CGSize(width: 660, height: 400)
    /// Centres of the two icons in the Finder window, in points, for a 128 pt icon size.
    static let appSlot = CGPoint(x: 170, y: 186)
    static let applicationsSlot = CGPoint(x: 490, y: 186)
    static let iconSize: CGFloat = 128

    static let skyTop = RGBA(0xF8FBF7)
    static let skyBottom = RGBA(0xE4F1E5)
    static let hillFar = RGBA(0xD3EAD7)
    static let hillFarBottom = RGBA(0xC2E1C8)
    /// The meadow the icons stand on: its crest, the band where the labels sit, and lower down.
    static let meadowCrest = RGBA(0x67A774)
    static let meadowLabels = RGBA(0x448257)
    static let meadowLow = RGBA(0x427F53)
    static let meadowRim = RGBA(0xA6D9A6, alpha: 0.9)
    /// A closer, darker swell across the bottom, for depth.
    static let frontTop = RGBA(0x3A7A4E)
    static let frontBottom = RGBA(0x2A6040)
    static let grassFarTip = RGBA(0xB9DEBF)
    static let grassFarRoot = RGBA(0xA4D2AD)
    static let grassTip = RGBA(0x8CCB86)
    static let grassRoot = RGBA(0x4F9161)
    static let grassFoldTip = RGBA(0xB2E09F)
    static let grassFoldRoot = RGBA(0x67A774)
    static let grassNearTip = RGBA(0x4C9A5C)
    static let grassNearRoot = RGBA(0x24573A)
    static let grassNearFoldTip = RGBA(0x67B46F)
    static let arrow = RGBA(0x3C9D5D)

    /// Where each crest runs, left to right (y at evenly spaced x across the 660 pt).
    static let meadowCrestLine: [CGFloat] = [252, 249, 245, 246, 248, 244, 241, 247]
    static let farHillLine: [CGFloat] = [226, 219, 224, 231, 228, 218, 214, 221]
    static let frontLine: [CGFloat] = [344, 336, 342, 356, 362, 352, 340, 334]

    /// Tufts of grass along the meadow's crest: centre, number of blades, tallest blade. They gather
    /// at the edges and behind the icons, so the icons look planted, and leave the arrow's span calm.
    static let crestTufts: [(x: CGFloat, blades: Int, height: CGFloat)] = [
        (14, 5, 30), (62, 3, 18), (112, 4, 26), (226, 4, 24), (276, 2, 12),
        (392, 2, 13), (430, 4, 25), (552, 4, 27), (606, 3, 18), (650, 5, 32),
    ]
    static let frontTufts: [(x: CGFloat, blades: Int, height: CGFloat)] = [
        (8, 6, 40), (64, 3, 22), (602, 3, 24), (654, 6, 42),
    ]

    /// Under each label, over the texture: a capsule in the mid tone that carries both label colours.
    /// Wide enough for "Applications" and for "Pasto.app" (extensions shown), and a few points taller
    /// than the label, since where exactly Finder puts it can vary by a point or two.
    static let labelPlateSize = CGSize(width: 124, height: 24)
    /// Label centre below the icon centre: half the icon, Finder's gap (about 4 pt), half a 13 pt line.
    static let labelCenterOffset: CGFloat = iconSize / 2 + 4 + 8
    static let labelPlate = RGBA(0x448257)
    static let labelPlateEdge = RGBA(0x6FAF7C, alpha: 0.55)

    /// - Parameter overTexture: true draws only what goes over the generated texture (the arrow and
    ///   the label plates); false draws the whole vector meadow.
    static func scene(overTexture: Bool = false) -> Scene {
        overTexture ? Scene(width: size.width, height: size.height, layers: [arrowLayer()]) : meadowScene()
    }

    private static func labelPlates() -> Layer {
        var items: [Item] = []
        for slot in [appSlot, applicationsSlot] {
            let rect = CGRect(x: slot.x - labelPlateSize.width / 2, y: slot.y + labelCenterOffset - labelPlateSize.height / 2,
                              width: labelPlateSize.width, height: labelPlateSize.height)
            let capsule = roundedRect(rect, radius: rect.height / 2)
            items.append(Item(path: capsule, paint: .solid(labelPlate)))
            // A hairline of light along the top, as on the meadow's crest.
            items.append(Item(path: capsule, paint: .vertical(labelPlateEdge, labelPlateEdge.opacity(0), from: rect.minY, to: rect.minY + 6),
                              strokeWidth: 2, clip: capsule))
        }
        return Layer(name: "label-plates", items: items, shadow: Shadow(dy: 1, blur: 6, color: RGBA(0x1D5A33, alpha: 0.18)))
    }

    /// A plain arrow between the two icons, along their row.
    private static func arrowLayer() -> Layer {
        let gap: CGFloat = iconSize / 2 + 34
        let start = CGPoint(x: appSlot.x + gap, y: appSlot.y)
        let end = CGPoint(x: applicationsSlot.x - gap, y: applicationsSlot.y)
        let (shaft, head) = arrowPaths(from: start, to: end, sag: 0, headLength: 15)
        return Layer(name: "arrow", items: [
            Item(path: shaft, paint: .solid(arrow), strokeWidth: 5),
            Item(path: head, paint: .solid(arrow), strokeWidth: 5),
        ])
    }

    private static func meadowScene() -> Scene {
        let bounds = CGRect(origin: .zero, size: size)
        var layers: [Layer] = []
        layers.append(Layer(name: "sky", items: [
            Item(path: CGPath(rect: bounds, transform: nil), paint: .vertical(skyTop, skyBottom, from: 0, to: 250)),
        ]))

        layers.append(Layer(name: "hill-far", items: [
            Item(path: ridge(farHillLine), paint: .vertical(hillFar, hillFarBottom, from: 212, to: 260)),
        ]))
        layers.append(Layer(name: "grass-far", items: tufts([(40, 3, 14), (176, 2, 10), (330, 3, 12), (500, 2, 11), (628, 3, 15)],
                                                            line: farHillLine, sink: 4).map {
            Item(path: $0.path, paint: .vertical(grassFarTip, grassFarRoot, from: 196, to: 232))
        }))

        // The meadow's tone is set by its gradient stops: lighter at the crest, the label tone a
        // little below it (where both label colours read), a touch darker further down.
        let crest = meadowCrestLine.min() ?? 240
        let meadow = ridge(meadowCrestLine)
        layers.append(Layer(name: "meadow", items: [
            Item(path: meadow, paint: .linear(
                from: CGPoint(x: 0, y: crest), to: CGPoint(x: 0, y: size.height),
                stops: [GradientStop(0, meadowCrest), GradientStop(0.09, meadowLabels), GradientStop(0.3, meadowLabels),
                        GradientStop(1, meadowLow)])),
            // A sunlit rim along the crest.
            Item(path: meadow, paint: .vertical(meadowRim, meadowRim.opacity(0), from: crest, to: crest + 10),
                 strokeWidth: 3, clip: meadow),
        ]))

        layers.append(Layer(name: "grass", items: tufts(crestTufts, line: meadowCrestLine, sink: 6).flatMap { blade in
            [Item(path: blade.path, paint: .vertical(grassTip, grassRoot, from: 210, to: 252)),
             Item(path: blade.fold, paint: .vertical(grassFoldTip, grassFoldRoot, from: 210, to: 252))]
        }))

        layers.append(Layer(name: "meadow-front", items: [
            Item(path: ridge(frontLine), paint: .vertical(frontTop, frontBottom, from: 334, to: size.height)),
        ], shadow: Shadow(dy: -2, blur: 14, color: RGBA(0x1D5A33, alpha: 0.22))))
        layers.append(Layer(name: "grass-near", items: tufts(frontTufts, line: frontLine, sink: 8).flatMap { blade in
            [Item(path: blade.path, paint: .vertical(grassNearTip, grassNearRoot, from: 300, to: 360)),
             Item(path: blade.fold, paint: .vertical(grassNearFoldTip, grassNearTip, from: 300, to: 360))]
        }))

        layers.append(arrowLayer())
        return Scene(width: size.width, height: size.height, layers: layers)
    }

    /// The background at `scale`, over the texture when there is one.
    static func render(scale: Int, texture: CGImage?) -> CGImage {
        Rasterizer.render(scene(overTexture: texture != nil), pixelWidth: Int(size.width) * scale,
                          pixelHeight: Int(size.height) * scale, underlay: texture)
    }

    /// The area under `line` (y values evenly spaced across the width), down to the bottom edge, with
    /// a smooth Catmull-Rom curve through the points.
    static func ridge(_ line: [CGFloat]) -> CGPath {
        let step = size.width / CGFloat(line.count - 1)
        let points = line.enumerated().map { CGPoint(x: CGFloat($0.offset) * step, y: $0.element) }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -2, y: size.height + 2))
        path.addLine(to: CGPoint(x: -2, y: points[0].y))
        path.addLine(to: points[0])
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)], p1 = points[index], p2 = points[index + 1], p3 = points[min(index + 2, points.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.addLine(to: CGPoint(x: size.width + 2, y: points[points.count - 1].y))
        path.addLine(to: CGPoint(x: size.width + 2, y: size.height + 2))
        path.closeSubpath()
        return path
    }

    /// The crest's height at `x`, interpolated linearly between the points of `line`.
    static func height(of line: [CGFloat], at x: CGFloat) -> CGFloat {
        let step = size.width / CGFloat(line.count - 1)
        let position = min(max(x / step, 0), CGFloat(line.count - 1))
        let index = min(Int(position), line.count - 2)
        let t = position - CGFloat(index)
        return line[index] + (line[index + 1] - line[index]) * t
    }

    /// Deterministic tufts of blades rooted `sink` below a crest line: in each tuft the blades fan
    /// out from the middle, the tallest near the centre, all nudged by a light breeze to the right.
    /// Returns each blade's outline and its lit half (the outside of its bend), as in the icon.
    private static func tufts(_ tufts: [(x: CGFloat, blades: Int, height: CGFloat)], line: [CGFloat],
                              sink: CGFloat) -> [(path: CGPath, fold: CGPath)] {
        let pattern: [CGFloat] = [0.62, 0.9, 1, 0.78, 0.55, 0.85]
        var result: [(CGPath, CGPath)] = []
        for (tuftIndex, tuft) in tufts.enumerated() {
            for blade in 0..<tuft.blades {
                // -1 … 1 across the tuft.
                let spread = tuft.blades == 1 ? 0 : CGFloat(blade) / CGFloat(tuft.blades - 1) * 2 - 1
                let x = tuft.x + spread * CGFloat(tuft.blades) * 3.2
                let height = tuft.height * pattern[(blade + tuftIndex) % pattern.count]
                let lean = spread * height * 0.42 + height * 0.16
                let width = max(4, tuft.height * 0.2)
                let outline = BladeOutline(Blade(x, width: width, height: height + sink, lean: lean,
                                                 stiffness: 0.45 + 0.1 * abs(spread)),
                                           baseY: self.height(of: line, at: x) + sink)
                result.append((outline.path, outline.half(left: lean >= 0)))
            }
        }
        return result
    }

    // MARK: Checks

    /// Mean WCAG relative luminance of `image` inside `rect` (points, y-down; `scale` pixels per point).
    static func meanLuminance(of image: CGImage, in rect: CGRect, scale: CGFloat) -> Double {
        let width = image.width, height = image.height
        let context = Rasterizer.makeContext(width: width, height: height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0 }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let bytesPerRow = context.bytesPerRow
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var total = 0.0, count = 0
        let x0 = max(Int(rect.minX * scale), 0), x1 = min(Int(rect.maxX * scale), width)
        let y0 = max(Int(rect.minY * scale), 0), y1 = min(Int(rect.maxY * scale), height)
        // The bitmap context's memory starts with the top row.
        for y in y0..<max(y1, y0) {
            for x in x0..<max(x1, x0) {
                let p = y * bytesPerRow + x * 4
                total += 0.2126 * linear(pixels[p]) + 0.7152 * linear(pixels[p + 1]) + 0.0722 * linear(pixels[p + 2])
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }

    /// The background at @2x with both icons in their slots and their labels, black and white, to
    /// check the layout without building a DMG (`dmg-inspect` draws the same from a real one).
    static func layoutPreview(icon: CGImage, texture: CGImage?) -> CGImage {
        let scale: CGFloat = 2
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let base = render(scale: 2, texture: texture)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height * 2, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = CGSize(width: size.width, height: size.height * 2)
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let folder = NSWorkspace.shared.icon(forFile: "/Applications")
        for (index, labelColor) in [NSColor.black, NSColor.white].enumerated() {
            let top = CGFloat(1 - index) * size.height
            context.cgContext.draw(base, in: CGRect(x: 0, y: top, width: size.width, height: size.height))
            func slotRect(_ center: CGPoint) -> NSRect {
                NSRect(x: center.x - iconSize / 2, y: top + size.height - center.y - iconSize / 2, width: iconSize, height: iconSize)
            }
            context.cgContext.draw(icon, in: slotRect(appSlot))
            folder.draw(in: slotRect(applicationsSlot))
            for (name, center) in [("Pasto", appSlot), ("Applications", applicationsSlot)] {
                let label = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: labelColor])
                let rect = slotRect(center)
                label.draw(at: NSPoint(x: center.x - label.size().width / 2, y: rect.minY - 4 - label.size().height))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage!
    }
}
