import AppKit

/// Chooses the background of a text card from the text's own colours.
nonisolated enum TextCardBackground {
    /// What the rule needs to know about a text, computed once when the model is built so that
    /// configuring a cell never walks the attributes again. A dynamic colour of the text (a
    /// catalogue colour such as the text colour) is resolved in the appearance that is current
    /// then, so the model is to be built in the appearance its card is drawn in.
    struct Summary: Sendable, Hashable {
        /// No run of the text carries any attribute.
        var isPlain: Bool
        /// The explicit text colour covering at least as many characters as those without one.
        var dominantForeground: ColorCode?
        /// The explicit background colour covering at least as many characters as those without one.
        var dominantBackground: ColorCode?

        static let plain = Summary(isPlain: true, dominantForeground: nil, dominantBackground: nil)
    }

    /// Background behind rich text whose dominant text colour is light.
    static let darkDefault = ColorCode(rawValue: 0x1E1E1E)
    /// Background behind rich text whose dominant text colour is dark.
    static let lightDefault = ColorCode(rawValue: 0xFFFFFF)

    static func summary(of text: NSAttributedString) -> Summary {
        var foreground = ColorVotes()
        var background = ColorVotes()
        var hasAttributes = false

        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            if !attributes.isEmpty { hasAttributes = true }
            foreground.add(attributes[.foregroundColor] as? NSColor, count: range.length)
            background.add(attributes[.backgroundColor] as? NSColor, count: range.length)
        }

        return Summary(
            isPlain: !hasAttributes,
            dominantForeground: foreground.dominant,
            dominantBackground: background.dominant
        )
    }

    static func resolve(_ summary: Summary, isDark: Bool) -> CardBackground {
        if summary.isPlain { return .plainText }

        // Characters without a colour of their own are drawn in the primary text colour, which is
        // light in dark mode and dark in light mode.
        let isForegroundLight = summary.dominantForeground?.isLight ?? isDark
        let background = summary.dominantBackground ?? (isForegroundLight ? darkDefault : lightDefault)
        return background.alpha < 1 ? .richTextFallback : .color(background)
    }
}

/// Counts how many characters each colour covers. An explicit colour wins a tie against "no
/// colour", and the first of two equally common explicit colours wins.
private nonisolated struct ColorVotes {
    private var counts: [NSColor: Int] = [:]
    private var order: [NSColor] = []
    private var unset = 0

    mutating func add(_ color: NSColor?, count: Int) {
        guard let color else {
            unset += count
            return
        }
        if counts[color] == nil { order.append(color) }
        counts[color, default: 0] += count
    }

    var dominant: ColorCode? {
        var best: (color: NSColor, count: Int)?
        for color in order {
            let count = counts[color, default: 0]
            if count > (best?.count ?? 0) { best = (color, count) }
        }
        guard let best, best.count >= unset else { return nil }
        return ColorCode(best.color)
    }
}

nonisolated extension ColorCode {
    /// `nil` for colours with no RGB form, such as patterns.
    init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        // A zero alpha byte reads back as opaque, so a fully clear colour keeps the smallest
        // alpha the encoding can express.
        let alpha = Double(rgb.alphaComponent)
        self.init(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent),
            alpha: alpha < 1 ? max(alpha, 1.0 / 255) : 1
        )
    }
}
