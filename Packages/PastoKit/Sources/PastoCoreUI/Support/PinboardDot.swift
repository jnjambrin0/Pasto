import AppKit

/// A pinboard's dot, drawn the same wherever it appears — a card's header, the Pin menu, the
/// tabs: a disc in the pinboard's colour ringed by a thin line of a darker shade of it.
public enum PinboardDot {
    private enum Metrics {
        /// The ring is this fraction of the image's side wide, and drawn inside it…
        static let ringWidthFraction: CGFloat = 0.05
        /// …in the colour with each sRGB component multiplied by this.
        static let ringDarkening: CGFloat = 0.8
    }

    /// The dot, `side` points square. The colour is resolved whenever the image is drawn, so
    /// a dynamic one follows the appearance it is drawn in.
    public static func image(color: NSColor, side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let ringWidth = side * Metrics.ringWidthFraction
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
            circle.lineWidth = ringWidth
            color.setFill()
            circle.fill()
            ringColor(of: color).setStroke()
            circle.stroke()
            return true
        }
    }

    /// The colour of the ring: `color` darkened, resolved in the appearance current when asked.
    static func ringColor(of color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        return NSColor(
            srgbRed: rgb.redComponent * Metrics.ringDarkening,
            green: rgb.greenComponent * Metrics.ringDarkening,
            blue: rgb.blueComponent * Metrics.ringDarkening,
            alpha: rgb.alphaComponent
        )
    }
}
