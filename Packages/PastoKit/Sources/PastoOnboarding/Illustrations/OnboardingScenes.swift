import PastoPermissions
import SwiftUI

/// The vector fallbacks of the two onboarding pictures that are not permission pictures, in the
/// 400 × 250 design space and with the composition of the generated ones.
enum OnboardingScenes {
    /// What Pasto is: a fan of five clip cards (text, link, picture, colour, file) rising from the
    /// grass, a few specks of pollen above.
    static func intro(_ p: IllustrationPainter) {
        let palette = p.palette
        for (x, y, r) in [(179.7, 32.8, 5.2), (122.4, 53.6, 3.4), (266.0, 48.4, 3.9)] {
            p.context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(palette.pollen))
        }

        p.grass(GrassBlade.row(from: -8, to: 410, spacing: 6.5, minimum: 34, maximum: 60, width: 11, seed: 3),
                baseY: 254, tip: palette.grassFarTip, root: palette.grassRoot)

        let sink: CGFloat = 186
        func bars(_ inner: IllustrationPainter, _ rect: CGRect, top: CGFloat, count: Int) {
            inner.textBars(in: CGRect(x: rect.minX + 11, y: rect.minY + top, width: rect.width - 22, height: 40),
                           count: count, height: 6.5, spacing: 7.5, widths: [1, 0.9, 0.96])
        }
        // Back to front: the outer cards, the inner ones, the middle one.
        p.card(CGRect(x: 34, y: 86, width: 72, height: 168), header: palette.blue, headerFraction: 0.17, rotation: -13,
               sinkFrom: sink) { inner, rect in bars(inner, rect, top: 52, count: 3) }
        p.card(CGRect(x: 294, y: 86, width: 72, height: 168), header: palette.pink, headerFraction: 0.17, rotation: 13,
               sinkFrom: sink) { inner, rect in
            let sheet = CGRect(x: rect.minX + 18, y: rect.minY + 44, width: rect.width - 36, height: 44)
            var page = Path()
            page.move(to: CGPoint(x: sheet.minX + 4, y: sheet.minY))
            page.addLine(to: CGPoint(x: sheet.maxX - 11, y: sheet.minY))
            page.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY + 11))
            page.addLine(to: CGPoint(x: sheet.maxX, y: sheet.maxY - 4))
            page.addQuadCurve(to: CGPoint(x: sheet.maxX - 4, y: sheet.maxY), control: CGPoint(x: sheet.maxX, y: sheet.maxY))
            page.addLine(to: CGPoint(x: sheet.minX + 4, y: sheet.maxY))
            page.addQuadCurve(to: CGPoint(x: sheet.minX, y: sheet.maxY - 4), control: CGPoint(x: sheet.minX, y: sheet.maxY))
            page.addLine(to: CGPoint(x: sheet.minX, y: sheet.minY + 4))
            page.addQuadCurve(to: CGPoint(x: sheet.minX + 4, y: sheet.minY), control: CGPoint(x: sheet.minX, y: sheet.minY))
            inner.context.fill(page, with: .color(palette.bar))
            var fold = Path()
            fold.move(to: CGPoint(x: sheet.maxX - 11, y: sheet.minY))
            fold.addLine(to: CGPoint(x: sheet.maxX - 11, y: sheet.minY + 11))
            fold.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY + 11))
            fold.closeSubpath()
            inner.context.fill(fold, with: .color(palette.ink.opacity(0.6)))
            inner.textBars(in: CGRect(x: rect.minX + 11, y: rect.minY + 100, width: rect.width - 22, height: 20),
                           count: 2, height: 6, spacing: 6.5, widths: [1, 0.9])
        }
        p.card(CGRect(x: 88, y: 66, width: 76, height: 176), header: palette.amber, headerFraction: 0.17, rotation: -7,
               sinkFrom: sink) { inner, rect in
            inner.context.draw(Text(Image(systemName: "link")).font(.system(size: 34, weight: .semibold)).foregroundColor(palette.ink),
                               at: CGPoint(x: rect.midX, y: rect.minY + 74))
        }
        p.card(CGRect(x: 236, y: 66, width: 76, height: 176), header: palette.purple, headerFraction: 0.17, rotation: 7,
               sinkFrom: sink) { inner, rect in
            inner.context.fill(Path(ellipseIn: CGRect(x: rect.midX - 20, y: rect.minY + 40, width: 40, height: 40)),
                               with: .color(palette.greenLight))
            bars(inner, rect, top: 92, count: 3)
        }
        p.card(CGRect(x: 156, y: 64, width: 88, height: 186), header: palette.green, headerFraction: 0.13, rotation: 0,
               shadowRadius: 10, shadowY: 5, sinkFrom: sink) { inner, rect in
            let picture = CGRect(x: rect.minX + 10, y: rect.minY + 35, width: rect.width - 20, height: 45)
            inner.context.drawLayer { layer in
                let shape = Path(roundedRect: picture, cornerRadius: 7, style: .continuous)
                layer.clip(to: shape)
                layer.fill(shape, with: .color(Color(illustrationHex: 0xDDEEFB)))
                layer.fill(Path(ellipseIn: CGRect(x: picture.maxX - 20, y: picture.minY + 5, width: 14, height: 14)), with: .color(palette.warm))
                var far = Path()
                far.move(to: CGPoint(x: picture.minX, y: picture.maxY - 15))
                far.addQuadCurve(to: CGPoint(x: picture.maxX, y: picture.maxY - 12), control: CGPoint(x: picture.minX + 22, y: picture.minY + 12))
                far.addLine(to: CGPoint(x: picture.maxX, y: picture.maxY))
                far.addLine(to: CGPoint(x: picture.minX, y: picture.maxY))
                layer.fill(far, with: .color(palette.greenLight))
                var near = Path()
                near.move(to: CGPoint(x: picture.minX + 4, y: picture.maxY))
                near.addQuadCurve(to: CGPoint(x: picture.maxX, y: picture.maxY - 16), control: CGPoint(x: picture.midX + 10, y: picture.maxY - 26))
                near.addLine(to: CGPoint(x: picture.maxX, y: picture.maxY))
                layer.fill(near, with: .color(palette.green))
            }
            bars(inner, rect, top: 90, count: 3)
        }

        p.grass(GrassBlade.row(from: -6, to: 410, spacing: 8, minimum: 22, maximum: 50, width: 12, seed: 5),
                baseY: 256, tip: palette.grassTip, root: palette.grassNearRoot)
    }

    /// Quick Start: ⇧ ⌘ V, the activation shortcut, above the panel rising from the bottom edge with
    /// its row of cards, the first one selected.
    static func quickStart(_ p: IllustrationPainter) {
        let palette = p.palette
        let keys: [(CGFloat, Text)] = [
            (64.3, Text(Image(systemName: "shift")).font(.system(size: 27, weight: .semibold))),
            (164.6, Text(Image(systemName: "command")).font(.system(size: 27, weight: .semibold))),
            (264.3, Text("V").font(.system(size: 30, weight: .semibold, design: .rounded))),
        ]
        for (x, glyph) in keys {
            p.key(CGRect(x: x, y: 27, width: 71.6, height: 71), glyph: glyph)
        }
        for x in [150.3, 250.0] {
            var plus = Path()
            plus.move(to: CGPoint(x: x - 4, y: 62))
            plus.addLine(to: CGPoint(x: x + 4, y: 62))
            plus.move(to: CGPoint(x: x, y: 58))
            plus.addLine(to: CGPoint(x: x, y: 66))
            p.context.stroke(plus, with: .color(palette.ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
        for (index, opacity) in [0.3, 0.6, 1.0].enumerated() {
            let y = 113 + CGFloat(index) * 12.5
            var chevron = Path()
            chevron.move(to: CGPoint(x: 189, y: y + 7))
            chevron.addLine(to: CGPoint(x: 200, y: y))
            chevron.addLine(to: CGPoint(x: 211, y: y + 7))
            p.context.stroke(chevron, with: .color(palette.greenLight.opacity(opacity)),
                             style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
        }

        p.grass(GrassBlade.row(from: -6, to: 410, spacing: 7, minimum: 14, maximum: 32, width: 10, seed: 13),
                baseY: 254, tip: palette.grassTip, root: palette.grassRoot)

        let panel = CGRect(x: 24, y: 151, width: 352, height: 140)
        p.shadowed(radius: 10, y: -3, strength: 0.7) {
            $0.fill(Path(roundedRect: panel, cornerRadius: 23, style: .continuous), with: .color(palette.panel))
        }
        let headers = [palette.blue, palette.amber, palette.green, palette.purple, palette.pink, palette.cyan]
        for (index, header) in headers.enumerated() {
            let frame = CGRect(x: 36 + CGFloat(index) * 55.5, y: 165, width: 48, height: 55)
            p.card(frame, header: header, radius: 8, headerFraction: 0.2, shadowRadius: 4, shadowY: 2) { inner, rect in
                inner.textBars(in: CGRect(x: rect.minX + 8, y: rect.minY + 19, width: rect.width - 16, height: 30),
                               count: 3, height: 5, spacing: 5.4, widths: [1, 1, 1])
            }
            if index == 0 {
                p.context.stroke(Path(roundedRect: frame.insetBy(dx: -1, dy: -1), cornerRadius: 9, style: .continuous),
                                 with: .color(palette.blue), lineWidth: 2)
            }
        }
    }
}
