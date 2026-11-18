import AppKit
import PastoCore

/// How an item looks, for the views outside the cards that must agree with them: the preview
/// shows the same placeholder title, pinboard colours and text background as the item's card.
public enum ItemPresentation {
    /// A fill behind text and whether it is light, which decides the appearance of what is
    /// drawn on it.
    public struct TextBackdrop {
        public let color: NSColor
        public let isLight: Bool
    }

    public static var primaryTextColor: NSColor { CardColor.primaryText }
    public static var secondaryTextColor: NSColor { CardColor.secondaryText }

    /// The name an item goes by while the user has not given it a title.
    public static func typeName(of item: Item) -> String {
        let fileCount = if case .files(let files) = item.preview { files.paths.count } else { 1 }
        return CardStrings().typeName(for: item.type, fileCount: fileCount)
    }

    public static func color(of pinboard: PinboardColor) -> NSColor {
        CardColor.pinboard(pinboard)
    }

    /// The text a text card shows: with its own formatting when the item has any, cut to what a
    /// card lays out.
    public nonisolated static func attributedText(of preview: TextPreview) -> NSAttributedString {
        ItemCellModel.Text(preview).attributedText
    }

    /// The compact form of a link's address that cards show.
    public nonisolated static func shortURL(for url: URL) -> String {
        ShortURL.string(for: url)
    }

    /// The background a text card gives `text`.
    public static func textBackdrop(of text: NSAttributedString, isDark: Bool) -> TextBackdrop {
        let background = TextCardBackground.resolve(TextCardBackground.summary(of: text), isDark: isDark)
        return TextBackdrop(
            color: CardColor.resolved(background),
            isLight: background.isLight(inDarkMode: isDark) ?? !isDark
        )
    }
}
