import CoreGraphics

/// Keeps the end of a text that does not fit, which is the part of a file path that matters.
///
/// It is an estimate from the width of one character, not a measurement of the actual text, so a
/// path made of wide characters can still overflow its last line.
nonisolated enum HeadTruncation {
    static let ellipsis = "…"

    /// How many characters fit in `lines` lines of `width`, taking every character to be as wide
    /// as `characterWidth` (the label uses the width of "/").
    static func capacity(lines: Int, width: CGFloat, characterWidth: CGFloat) -> Int {
        guard characterWidth > 0, width > 0 else { return 0 }
        return lines * Int((width / characterWidth).rounded(.down))
    }

    /// `text` itself when it fits; otherwise an ellipsis followed by its last `capacity` characters.
    static func truncate(_ text: String, capacity: Int) -> String {
        guard text.count > capacity else { return text }
        return ellipsis + text.suffix(max(capacity, 0))
    }
}
