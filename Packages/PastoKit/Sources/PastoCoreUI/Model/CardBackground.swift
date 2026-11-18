/// What fills a card behind its content. The card's appearance follows the fill: content on a
/// light fill is drawn as in light mode and vice versa, whatever the system mode is.
nonisolated enum CardBackground: Sendable, Hashable {
    /// The system text background, with the window's appearance. Every card but text and colour.
    case standard
    /// Plain text: near black in dark mode, white in light mode.
    case plainText
    /// Rich text whose own background is translucent: the window background in dark mode, white
    /// in light mode.
    case richTextFallback
    /// A colour of the content itself: a colour item, or the dominant background of rich text.
    case color(ColorCode)

    /// Whether the fill is light, which decides the appearance of the card's content.
    /// `nil` means "whatever the window uses".
    func isLight(inDarkMode isDark: Bool) -> Bool? {
        switch self {
        case .standard: nil
        case .plainText, .richTextFallback: !isDark
        case .color(let code): code.isLight
        }
    }
}
