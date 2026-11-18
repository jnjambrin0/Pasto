import AppKit

/// How the preview makes a text readable on the background it shows it on. A run with a colour of
/// its own keeps it. A run without one is drawn black or white when it has a background of its
/// own — whichever reads on that background laid over the preview's — and in the primary text
/// colour otherwise.
nonisolated enum TextRecoloring {
    /// - Parameters:
    ///   - background: The preview's background, resolved for the appearance it is drawn in.
    ///   - primary: The colour of runs with neither a colour nor a background of their own.
    static func readable(_ text: NSAttributedString, on background: NSColor, primary: NSColor) -> NSAttributedString {
        var colors: [(range: NSRange, color: NSColor)] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            guard attributes[.foregroundColor] == nil else { return }
            let color = (attributes[.backgroundColor] as? NSColor)
                .flatMap { contrastingColor(on: $0, over: background) }
            colors.append((range, color ?? primary))
        }
        let result = NSMutableAttributedString(attributedString: text)
        for (range, color) in colors {
            result.addAttribute(.foregroundColor, value: color, range: range)
        }
        return result
    }

    /// Black on a light background and white on a dark one, the run's background composed over
    /// the preview's. `nil` for a run background with no RGB form, such as a pattern, which is
    /// then treated as no background.
    static func contrastingColor(on runBackground: NSColor, over background: NSColor) -> NSColor? {
        guard let top = runBackground.usingColorSpace(.deviceRGB) else { return nil }
        let bottom = background.usingColorSpace(.deviceRGB) ?? top
        let alpha = top.alphaComponent
        func composed(_ top: CGFloat, _ bottom: CGFloat) -> CGFloat {
            top * alpha + bottom * (1 - alpha)
        }
        let lightness = 0.299 * composed(top.redComponent, bottom.redComponent)
            + 0.587 * composed(top.greenComponent, bottom.greenComponent)
            + 0.114 * composed(top.blueComponent, bottom.blueComponent)
        return lightness > PreviewMetrics.textOnBackgroundLightnessThreshold ? .black : .white
    }
}
