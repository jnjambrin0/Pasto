import AppKit
import PastoCore
import PastoCoreUI

/// What a row's card shows: its text and, for some items, a small picture at its trailing edge.
///
/// The card's fill follows from the text. Formatted text gets the background a text card of the
/// panel would give it — white or near black for text without attributes, the text's own
/// background otherwise — and everything else the system's text background.
struct StackCardContent: Equatable {
    enum Text: Equatable {
        /// A text item's own text, with its formatting.
        case rich(NSAttributedString)
        case plain(String)
    }

    enum Thumb: Equatable {
        case color(ColorCode)
        /// The name of an SF Symbol.
        case symbol(String)
        /// An encoded image shown small and whole, such as a site's icon.
        case icon(Data)
        /// An encoded image that fills the thumb.
        case image(Data)
    }

    var text: Text
    var thumb: Thumb?

    init(text: Text, thumb: Thumb? = nil) {
        self.text = text
        self.thumb = thumb
    }

    /// - Parameters:
    ///   - isPlainText: Whether the stack pastes text without its formatting; its cards then show
    ///     it without formatting too.
    ///   - isLinkPreviewsOn: Whether the app may show what it learnt about a link's page, such as
    ///     the site's icon.
    init(item: Item, isPlainText: Bool, isLinkPreviewsOn: Bool) {
        switch item.preview {
        case .text(let preview):
            let text = ItemPresentation.attributedText(of: preview)
            self.init(text: isPlainText ? .plain(text.string) : .rich(text))
        case .link(let link):
            let icon = isLinkPreviewsOn ? link.iconData.map(Thumb.icon) : nil
            self.init(text: .plain(ItemPresentation.shortURL(for: link.url)), thumb: icon ?? .symbol("link"))
        case .image(let image):
            // An image preview may lack a thumbnail; a symbol then stands in for it.
            self.init(
                text: .plain(ItemPresentation.typeName(of: item)),
                thumb: image.thumbnailData.map(Thumb.image) ?? .symbol("photo")
            )
        case .color(let color):
            let code = ColorCode(truncating: color.colorCode)
            self.init(text: .plain(code.hexString), thumb: .color(code))
        case .files(let files):
            // One file by its path; several by how many there are.
            let text = files.paths.count == 1 ? files.paths[0] : ItemPresentation.typeName(of: item)
            self.init(text: .plain(text), thumb: .symbol("doc"))
        case .unknown:
            self.init(text: .plain(StackStrings.unknownContent))
        }
    }
}
