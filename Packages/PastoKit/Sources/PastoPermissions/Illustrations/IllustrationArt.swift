import SwiftUI

/// The colours of the vector illustrations, in light and dark. The light values are the palette
/// the generated pictures were made with, so both kinds of art look alike.
package struct IllustrationPalette: Sendable {
    package var backgroundTop: Color
    package var backgroundBottom: Color
    package var paper: Color
    package var paperShade: Color
    /// Rounded bars that stand for text, and the stronger ink for labels and symbols.
    package var bar: Color
    package var ink: Color
    package var titleBar: Color
    package var keyFace: Color
    package var keyGlyph: Color
    package var shadow: Color
    package var grassTip: Color
    package var grassRoot: Color
    package var grassFarTip: Color
    package var grassFarRoot: Color
    package var grassNearTip: Color
    package var grassNearRoot: Color
    /// Where cards sink into the grass they take on this tint.
    package var grassTint: Color
    package var green: Color
    package var greenLight: Color
    package var greenDeep: Color
    package var warm: Color
    package var blue: Color
    package var amber: Color
    package var purple: Color
    package var pink: Color
    package var cyan: Color
    package var panel: Color
    /// Specks of light floating over the intro's cards.
    package var pollen: Color

    package static let light = IllustrationPalette(
        backgroundTop: Color(illustrationHex: 0xF6FBF5), backgroundBottom: Color(illustrationHex: 0xE3F2E4),
        paper: Color(illustrationHex: 0xFFFFFF), paperShade: Color(illustrationHex: 0xF0F7F2),
        bar: Color(illustrationHex: 0xDCEDE1), ink: Color(illustrationHex: 0xA9D3B4),
        titleBar: Color(illustrationHex: 0xEEF2EE), keyFace: Color(illustrationHex: 0xFFFFFF), keyGlyph: Color(illustrationHex: 0x137645),
        shadow: Color(illustrationHex: 0x04381F, opacity: 0.18),
        grassTip: Color(illustrationHex: 0x7DD46A), grassRoot: Color(illustrationHex: 0x2BA65B),
        grassFarTip: Color(illustrationHex: 0xBCE985), grassFarRoot: Color(illustrationHex: 0x7DD46A),
        grassNearTip: Color(illustrationHex: 0x2BA65B), grassNearRoot: Color(illustrationHex: 0x137645),
        grassTint: Color(illustrationHex: 0x7DB590, opacity: 0.55),
        green: Color(illustrationHex: 0x2BA65B), greenLight: Color(illustrationHex: 0x7DD46A), greenDeep: Color(illustrationHex: 0x0A6B4A),
        warm: Color(illustrationHex: 0xFFB23E), blue: Color(illustrationHex: 0x0A84FF), amber: Color(illustrationHex: 0xFFB23E),
        purple: Color(illustrationHex: 0xBF5AF2), pink: Color(illustrationHex: 0xFF375F), cyan: Color(illustrationHex: 0x64D2FF),
        panel: Color(illustrationHex: 0xFFFFFF, opacity: 0.7), pollen: Color(illustrationHex: 0xFFFFFF, opacity: 0.85))

    /// A night meadow: deep green backdrop, slate paper, the same accents a little softer.
    package static let dark = IllustrationPalette(
        backgroundTop: Color(illustrationHex: 0x15281E), backgroundBottom: Color(illustrationHex: 0x0E1C15),
        paper: Color(illustrationHex: 0x2E3832), paperShade: Color(illustrationHex: 0x27302B),
        bar: Color(illustrationHex: 0x3E4C43), ink: Color(illustrationHex: 0x5C8268),
        titleBar: Color(illustrationHex: 0x363F39), keyFace: Color(illustrationHex: 0x313B35), keyGlyph: Color(illustrationHex: 0x8FD98A),
        shadow: Color(illustrationHex: 0x000000, opacity: 0.42),
        grassTip: Color(illustrationHex: 0x4FA65A), grassRoot: Color(illustrationHex: 0x1B6B3C),
        grassFarTip: Color(illustrationHex: 0x3C7D47), grassFarRoot: Color(illustrationHex: 0x1F5534),
        grassNearTip: Color(illustrationHex: 0x23824A), grassNearRoot: Color(illustrationHex: 0x0D4127),
        grassTint: Color(illustrationHex: 0x1F5534, opacity: 0.6),
        green: Color(illustrationHex: 0x35B266), greenLight: Color(illustrationHex: 0x7DD46A), greenDeep: Color(illustrationHex: 0x0F5A3C),
        warm: Color(illustrationHex: 0xFFB23E), blue: Color(illustrationHex: 0x2B95FF), amber: Color(illustrationHex: 0xF5A93A),
        purple: Color(illustrationHex: 0xB65DE8), pink: Color(illustrationHex: 0xF0456A), cyan: Color(illustrationHex: 0x5AC4EE),
        panel: Color(illustrationHex: 0xFFFFFF, opacity: 0.07), pollen: Color(illustrationHex: 0xD9F2D2, opacity: 0.3))

    package static func forScheme(_ scheme: ColorScheme) -> IllustrationPalette {
        scheme == .dark ? .dark : .light
    }
}

extension Color {
    package init(illustrationHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// One blade of grass: a tapering ribbon around a curved spine that leaves the ground upright and
/// bends towards its tip, the outside of the bend keeping more width. The same construction as the
/// disk image background's blades (Tools/IconKit, `BladeOutline`).
package struct GrassBlade: Sendable {
    package var x: CGFloat
    package var width: CGFloat
    package var height: CGFloat
    package var lean: CGFloat
    package var stiffness: CGFloat = 0.5

    package init(_ x: CGFloat, width: CGFloat, height: CGFloat, lean: CGFloat, stiffness: CGFloat = 0.5) {
        self.x = x
        self.width = width
        self.height = height
        self.lean = lean
        self.stiffness = stiffness
    }

    package func path(baseY: CGFloat) -> Path {
        let base = CGPoint(x: x, y: baseY)
        let tip = CGPoint(x: x + lean, y: baseY - height)
        let knee = CGPoint(x: x, y: baseY - height * stiffness)
        let c1 = CGPoint(x: base.x + (knee.x - base.x) * 2 / 3, y: base.y + (knee.y - base.y) * 2 / 3)
        let c2 = CGPoint(x: tip.x + (knee.x - tip.x) * 2 / 3, y: tip.y + (knee.y - tip.y) * 2 / 3)
        func leftNormal(_ a: CGPoint, _ b: CGPoint) -> CGVector {
            let dx = b.x - a.x, dy = b.y - a.y, length = max(hypot(dx, dy), 0.0001)
            return CGVector(dx: dy / length, dy: -dx / length)
        }
        let n1 = leftNormal(base, knee), n2 = leftNormal(knee, tip)
        let half = width / 2
        let outerIsLeft = lean >= 0
        let outer: (CGFloat, CGFloat) = (0.95, 0.45), inner: (CGFloat, CGFloat) = (0.80, 0.20)
        let l = outerIsLeft ? outer : inner, r = outerIsLeft ? inner : outer
        func offset(_ p: CGPoint, _ n: CGVector, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + n.dx * d, y: p.y + n.dy * d) }
        var path = Path()
        path.move(to: CGPoint(x: base.x - half, y: base.y))
        path.addCurve(to: tip, control1: offset(c1, n1, half * l.0), control2: offset(c2, n2, half * l.1))
        path.addCurve(to: CGPoint(x: base.x + half, y: base.y), control1: offset(c2, n2, -half * r.1), control2: offset(c1, n1, -half * r.0))
        path.closeSubpath()
        return path
    }

    /// A deterministic row of blades between `from` and `to`, leaning gently to the right (the brand's
    /// breeze), with heights between `minimum` and `maximum`.
    package static func row(from: CGFloat, to: CGFloat, spacing: CGFloat, minimum: CGFloat, maximum: CGFloat,
                            width: CGFloat, seed: UInt32) -> [GrassBlade] {
        var state = seed &* 2_654_435_761 | 1
        func random() -> CGFloat {
            state = state &* 1_664_525 &+ 1_013_904_223
            return CGFloat(state >> 8) / CGFloat(1 << 24)
        }
        var blades: [GrassBlade] = []
        var x = from
        while x <= to {
            let height = minimum + (maximum - minimum) * random()
            let lean = height * (0.18 + 0.32 * random()) * (random() < 0.15 ? -0.6 : 1)
            blades.append(GrassBlade(x + spacing * 0.4 * (random() - 0.5), width: width * (0.8 + 0.4 * random()),
                                     height: height, lean: lean, stiffness: 0.4 + 0.2 * random()))
            x += spacing
        }
        return blades
    }
}

/// Drawing helpers for the vector illustrations. Every call takes design-space coordinates (the
/// 400 × 250 space of `IllustrationMetrics.designSize`); `IllustrationCanvas` scales it to the frame.
package struct IllustrationPainter {
    package var context: GraphicsContext
    package let palette: IllustrationPalette

    /// The soft, slightly green shadow of cards and windows, offset downwards.
    package func shadowed(radius: CGFloat = 8, y: CGFloat = 4, strength: Double = 1, _ draw: (inout GraphicsContext) -> Void) {
        var layer = context
        layer.addFilter(.shadow(color: palette.shadow.opacity(strength), radius: radius, x: 0, y: y))
        draw(&layer)
    }

    package func roundedRect(_ rect: CGRect, radius: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }

    /// A rounded bar standing for a line of text.
    package func bar(_ rect: CGRect, color: Color? = nil) {
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(color ?? palette.bar))
    }

    /// Three to four text bars filling `rect` from the top.
    package func textBars(in rect: CGRect, count: Int, height: CGFloat, spacing: CGFloat, widths: [CGFloat] = [1, 0.86, 0.94, 0.7]) {
        for index in 0..<count {
            let width = rect.width * widths[index % widths.count]
            bar(CGRect(x: rect.minX, y: rect.minY + CGFloat(index) * (height + spacing), width: width, height: height))
        }
    }

    /// A clip card: paper with a coloured band across its top. `content` draws in the card's own,
    /// unrotated frame. Rotation is in degrees, clockwise, around the card's centre.
    package func card(_ frame: CGRect, header: Color, radius: CGFloat? = nil, headerFraction: CGFloat = 0.2,
                      rotation: Double = 0, shadowRadius: CGFloat = 8, shadowY: CGFloat = 4, opacity: Double = 1,
                      sinkFrom: CGFloat? = nil, content: (IllustrationPainter, CGRect) -> Void = { _, _ in }) {
        var local = context
        local.opacity = opacity
        local.translateBy(x: frame.midX, y: frame.midY)
        local.rotate(by: .degrees(rotation))
        let rect = CGRect(x: -frame.width / 2, y: -frame.height / 2, width: frame.width, height: frame.height)
        let shape = roundedRect(rect, radius: radius ?? frame.width * 0.12)
        let painter = IllustrationPainter(context: local, palette: palette)
        painter.shadowed(radius: shadowRadius, y: shadowY) {
            $0.fill(shape, with: .linearGradient(Gradient(colors: [palette.paper, palette.paperShade]),
                                                 startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        }
        local.drawLayer { layer in
            layer.clip(to: shape)
            layer.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * headerFraction)),
                       with: .color(header))
            let inner = IllustrationPainter(context: layer, palette: palette)
            content(inner, rect)
            if let sinkFrom {
                // Where the card sinks into the grass, it takes on the grass's shade.
                let start = rect.minY + (sinkFrom - frame.minY)
                layer.fill(Path(rect), with: .linearGradient(Gradient(colors: [palette.grassTint.opacity(0), palette.grassTint]),
                                                             startPoint: CGPoint(x: 0, y: start), endPoint: CGPoint(x: 0, y: rect.maxY)))
            }
        }
    }

    /// A simplified macOS window: rounded white body, a light title bar with the three lights.
    /// Returns the body's rect (below the title bar).
    @discardableResult
    package func window(_ frame: CGRect, radius: CGFloat = 12, titleBarHeight: CGFloat = 20) -> CGRect {
        let shape = roundedRect(frame, radius: radius)
        shadowed(radius: 10, y: 5) { $0.fill(shape, with: .color(palette.paper)) }
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.fill(Path(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: titleBarHeight)),
                       with: .color(palette.titleBar))
        }
        let lights: [Color] = [Color(illustrationHex: 0xFF5F57), Color(illustrationHex: 0xFEBC2E), Color(illustrationHex: 0x28C840)]
        let diameter = titleBarHeight * 0.42
        for (index, color) in lights.enumerated() {
            let center = CGPoint(x: frame.minX + titleBarHeight * 0.62 + CGFloat(index) * diameter * 1.65,
                                 y: frame.minY + titleBarHeight / 2)
            context.fill(Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)),
                         with: .color(color))
        }
        return CGRect(x: frame.minX, y: frame.minY + titleBarHeight, width: frame.width, height: frame.height - titleBarHeight)
    }

    /// A keyboard key: a white rounded square with a lighter top edge and a soft shadow, and one glyph.
    package func key(_ frame: CGRect, glyph: Text) {
        let shape = roundedRect(frame, radius: frame.width * 0.24)
        shadowed(radius: 7, y: 4) { $0.fill(shape, with: .color(palette.keyFace)) }
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.fill(Path(CGRect(x: frame.minX, y: frame.maxY - frame.height * 0.12, width: frame.width, height: frame.height * 0.12)),
                       with: .color(palette.shadow.opacity(0.25)))
        }
        context.stroke(roundedRect(frame.insetBy(dx: 0.75, dy: 0.75), radius: frame.width * 0.24),
                       with: .linearGradient(Gradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0)]),
                                             startPoint: CGPoint(x: 0, y: frame.minY), endPoint: CGPoint(x: 0, y: frame.minY + 10)),
                       lineWidth: 1.5)
        context.draw(glyph.foregroundColor(palette.keyGlyph), at: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// A four-pointed sparkle.
    package func sparkle(at center: CGPoint, radius: CGFloat, color: Color) {
        var path = Path()
        let waist = radius * 0.22
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + waist, y: center.y - waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - waist, y: center.y - waist))
        context.fill(path, with: .color(color))
    }

    /// A row of grass blades rooted at `baseY`, darkening towards the roots. The ground below the
    /// roots is filled too, so the row reaches any frame's bottom edge.
    package func grass(_ blades: [GrassBlade], baseY: CGFloat, tip: Color, root: Color, fillsGround: Bool = true) {
        let tallest = blades.map(\.height).max() ?? 0
        let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: [tip, root]),
                                                             startPoint: CGPoint(x: 0, y: baseY - tallest), endPoint: CGPoint(x: 0, y: baseY))
        for blade in blades {
            context.fill(blade.path(baseY: baseY + 1), with: shading)
        }
        if fillsGround {
            context.fill(Path(CGRect(x: -400, y: baseY, width: 1200, height: 400)), with: .color(root))
        }
    }
}

/// Draws a vector illustration: the background fills the whole frame and the scene, drawn in the
/// 400 × 250 design space, is scaled to cover it and centred.
package struct IllustrationCanvas: View {
    package let draw: (IllustrationPainter) -> Void
    @Environment(\.colorScheme) private var colorScheme

    package init(draw: @escaping (IllustrationPainter) -> Void) {
        self.draw = draw
    }

    package var body: some View {
        let palette = IllustrationPalette.forScheme(colorScheme)
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [palette.backgroundTop, palette.backgroundBottom]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let design = IllustrationMetrics.designSize
            let scale = max(size.width / design.width, size.height / design.height)
            var scene = context
            scene.translateBy(x: (size.width - design.width * scale) / 2, y: (size.height - design.height * scale) / 2)
            scene.scaleBy(x: scale, y: scale)
            draw(IllustrationPainter(context: scene, palette: palette))
        }
    }
}
