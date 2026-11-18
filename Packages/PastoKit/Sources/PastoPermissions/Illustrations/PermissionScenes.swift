import SwiftUI

/// The vector fallbacks of the permission pictures, drawn in the 400 × 250 design space with the
/// same composition as the generated pictures, so either one tells the same.
package enum PermissionScenes {
    /// Paste into other apps: a clip card travels along an arrow into a window, where its text lands
    /// (two highlighted lines and the text cursor); the Return key below.
    package static func accessibility(_ p: IllustrationPainter) {
        let palette = p.palette
        p.grass(GrassBlade.row(from: -6, to: 44, spacing: 9, minimum: 18, maximum: 40, width: 12, seed: 2),
                baseY: 252, tip: palette.grassTip, root: palette.grassRoot, fillsGround: false)

        let body = p.window(CGRect(x: 186, y: 26, width: 171, height: 132), radius: 13, titleBarHeight: 21)
        for line in 0..<6 {
            let rect = CGRect(x: body.minX + 17, y: body.minY + 14 + CGFloat(line) * 15.6, width: body.width - 34, height: 9)
            p.bar(rect, color: line == 2 || line == 3 ? palette.greenLight.opacity(0.45) : palette.bar)
        }
        // The text cursor where the pasted text ends.
        p.context.fill(Path(roundedRect: CGRect(x: body.maxX - 20, y: body.minY + 14 + 3 * 15.6 - 2, width: 2.2, height: 13),
                            cornerRadius: 1.1), with: .color(palette.blue))

        p.card(CGRect(x: 52, y: 40, width: 104, height: 125), header: palette.green, rotation: -6,
               shadowRadius: 12, shadowY: 7) { inner, rect in
            inner.textBars(in: CGRect(x: rect.minX + 16, y: rect.minY + 44, width: rect.width - 32, height: 70),
                           count: 4, height: 9, spacing: 8.5, widths: [1, 1, 1, 1])
        }

        var arrow = Path()
        arrow.move(to: CGPoint(x: 150, y: 106))
        arrow.addQuadCurve(to: CGPoint(x: 199, y: 103), control: CGPoint(x: 172, y: 86))
        p.context.stroke(arrow, with: .color(palette.green), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        var head = Path()
        head.move(to: CGPoint(x: 190, y: 94))
        head.addLine(to: CGPoint(x: 199.5, y: 103.5))
        head.addLine(to: CGPoint(x: 187, y: 107.5))
        p.context.stroke(head, with: .color(palette.green), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        p.key(CGRect(x: 240, y: 169, width: 60, height: 53),
              glyph: Text(Image(systemName: "return")).font(.system(size: 24, weight: .semibold)))
    }

    /// Reading the clipboard: cards arrive along a dotted arc into a clipboard, which carries a check
    /// badge; a low line of grass along the bottom.
    package static func pasteboard(_ p: IllustrationPainter) {
        let palette = p.palette
        p.grass(GrassBlade.row(from: -8, to: 410, spacing: 7, minimum: 12, maximum: 26, width: 9, seed: 7),
                baseY: 252, tip: palette.grassFarTip, root: palette.grassRoot)
        p.grass(GrassBlade.row(from: -4, to: 410, spacing: 9, minimum: 8, maximum: 17, width: 10, seed: 11),
                baseY: 252, tip: palette.grassTip, root: palette.grassNearRoot)

        // The cards' path, dotted, ending in a small arrowhead at the clipboard.
        var arc = Path()
        arc.move(to: CGPoint(x: 367, y: 133))
        arc.addQuadCurve(to: CGPoint(x: 183, y: 108), control: CGPoint(x: 300, y: 80))
        p.context.stroke(arc, with: .color(palette.ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [0.1, 6.5]))
        var head = Path()
        head.move(to: CGPoint(x: 190, y: 100))
        head.addLine(to: CGPoint(x: 179, y: 108))
        head.addLine(to: CGPoint(x: 191, y: 114))
        p.context.stroke(head, with: .color(palette.ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

        let board = CGRect(x: 41, y: 40, width: 131, height: 161)
        p.shadowed(radius: 12, y: 7) {
            $0.fill(p.roundedRect(board, radius: 20),
                    with: .linearGradient(Gradient(colors: [palette.green.opacity(0.92), palette.green]),
                                          startPoint: CGPoint(x: 0, y: board.minY), endPoint: CGPoint(x: 0, y: board.maxY)))
        }
        let sheet = CGRect(x: 53, y: 55, width: 108, height: 130)
        p.context.fill(p.roundedRect(sheet, radius: 10), with: .color(palette.paper))
        for line in 0..<5 {
            p.bar(CGRect(x: sheet.minX + 13, y: sheet.minY + 20 + CGFloat(line) * 18.5, width: line == 4 ? 70 : 82, height: 9))
        }
        p.context.fill(p.roundedRect(CGRect(x: 81, y: 27, width: 54, height: 26), radius: 9), with: .color(palette.greenDeep))

        p.card(CGRect(x: 312, y: 82, width: 36, height: 44), header: palette.blue, rotation: 22, shadowRadius: 5, shadowY: 3) { inner, rect in
            inner.textBars(in: CGRect(x: rect.minX + 6, y: rect.minY + 14, width: rect.width - 12, height: 24),
                           count: 3, height: 3.6, spacing: 3.6, widths: [1, 0.9, 0.8])
        }
        p.card(CGRect(x: 267, y: 56, width: 46, height: 60), header: palette.amber, rotation: 8, shadowRadius: 6, shadowY: 4) { inner, rect in
            inner.textBars(in: CGRect(x: rect.minX + 8, y: rect.minY + 19, width: rect.width - 16, height: 30),
                           count: 3, height: 4.6, spacing: 4.6, widths: [1, 0.95, 0.9])
        }
        p.card(CGRect(x: 197, y: 46, width: 57, height: 70), header: palette.purple, rotation: -12, shadowRadius: 8, shadowY: 5) { inner, rect in
            inner.textBars(in: CGRect(x: rect.minX + 9, y: rect.minY + 22, width: rect.width - 18, height: 36),
                           count: 3, height: 5.6, spacing: 5.4, widths: [1, 1, 1])
        }

        let badge = CGRect(x: 131, y: 151, width: 50, height: 50)
        p.shadowed(radius: 8, y: 4) { $0.fill(Path(ellipseIn: badge), with: .color(palette.paper)) }
        p.context.draw(Text(Image(systemName: "checkmark")).font(.system(size: 22, weight: .heavy)).foregroundColor(palette.green),
                       at: CGPoint(x: badge.midX, y: badge.midY + 0.5))
    }

    /// Suggestions: a window with a form whose middle field is focused; below, a row of cards, the
    /// middle one raised in a warm halo, with a glowing line from it to the field; a padlock chip
    /// says it all stays on the Mac.
    package static func suggestions(_ p: IllustrationPainter) {
        let palette = p.palette
        let body = p.window(CGRect(x: 75, y: 19, width: 249, height: 111), radius: 13, titleBarHeight: 21)
        for row in 0..<3 {
            let y = body.minY + 13 + CGFloat(row) * 24
            p.bar(CGRect(x: body.minX + 19, y: y + 3, width: 54, height: 8), color: palette.ink.opacity(0.75))
            let field = CGRect(x: body.minX + 82, y: y - 1, width: 149, height: 15.5)
            let focused = row == 1
            p.context.stroke(Path(roundedRect: field, cornerRadius: 5.5), with: .color(focused ? palette.blue : palette.bar),
                             lineWidth: focused ? 2 : 1.4)
            if focused {
                p.context.fill(Path(CGRect(x: field.minX + 8, y: field.minY + 3.5, width: 1.6, height: 8.5)), with: .color(palette.blue))
            }
        }

        // The halo around the suggested card, amber to coral to green: concentric rounded rings that
        // fade outwards, which reads as a glow without any blur.
        let highlight = CGRect(x: 156, y: 157, width: 59, height: 69)
        let glow = Gradient(colors: [palette.warm, Color(illustrationHex: 0xFF7A59), palette.greenLight, palette.greenLight,
                                     palette.warm])
        for ring in 0..<9 {
            let inset = -1.5 - CGFloat(ring) * 1.6
            var layer = p.context
            layer.opacity = 0.42 * pow(0.72, Double(ring))
            layer.stroke(Path(roundedRect: highlight.insetBy(dx: inset, dy: inset), cornerRadius: 9 - inset, style: .continuous),
                         with: .conicGradient(glow, center: CGPoint(x: highlight.midX, y: highlight.midY), angle: .degrees(200)),
                         style: StrokeStyle(lineWidth: 2.2))
        }

        let others: [(CGFloat, Color)] = [(45, palette.blue), (100, palette.amber), (226, palette.purple), (280, palette.pink)]
        for (x, color) in others {
            p.card(CGRect(x: x, y: 163, width: 46, height: 56), header: color.opacity(0.7), headerFraction: 0.2,
                   shadowRadius: 4, shadowY: 2, opacity: 0.75) { inner, rect in
                inner.textBars(in: CGRect(x: rect.minX + 7, y: rect.minY + 19, width: rect.width - 14, height: 30),
                               count: 3, height: 4.6, spacing: 5.8, widths: [1, 1, 1])
            }
        }
        p.card(highlight, header: palette.green, headerFraction: 0.2, shadowRadius: 9, shadowY: 5) { inner, rect in
            inner.textBars(in: CGRect(x: rect.minX + 8, y: rect.minY + 22, width: rect.width - 16, height: 36),
                           count: 3, height: 6, spacing: 6.6, widths: [1, 1, 1])
        }

        // The glowing line from the card to the field.
        var line = Path()
        line.move(to: CGPoint(x: 185, y: 156))
        line.addCurve(to: CGPoint(x: 276, y: 86), control1: CGPoint(x: 196, y: 120), control2: CGPoint(x: 262, y: 128))
        p.context.stroke(line, with: .color(palette.warm.opacity(0.3)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        p.context.stroke(line, with: .color(palette.warm), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        p.sparkle(at: CGPoint(x: 277, y: 85), radius: 6.5, color: palette.warm)
        p.sparkle(at: CGPoint(x: 155, y: 148), radius: 9.5, color: palette.warm)
        p.sparkle(at: CGPoint(x: 165, y: 140), radius: 3.6, color: palette.warm)
        p.sparkle(at: CGPoint(x: 171.5, y: 146.5), radius: 2.6, color: palette.warm)

        let chip = CGRect(x: 335, y: 171, width: 35, height: 34)
        p.shadowed(radius: 5, y: 3) { $0.fill(p.roundedRect(chip, radius: 9), with: .color(palette.paperShade)) }
        p.context.draw(Text(Image(systemName: "lock.fill")).font(.system(size: 17, weight: .semibold)).foregroundColor(palette.keyGlyph),
                       at: CGPoint(x: chip.midX, y: chip.midY))
    }
}
