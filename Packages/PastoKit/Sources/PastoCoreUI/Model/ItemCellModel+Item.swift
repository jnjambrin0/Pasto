import AppKit
import PastoCore

public nonisolated extension ItemCellModel {
    /// Builds the model of an item's card. Pure: it reads nothing but its arguments, so it can run
    /// off the main thread. Rich text is parsed here, once, rather than when a cell is configured.
    init(item: Item, context: ItemCellContext) {
        self.init(item: item, context: context, strings: CardStrings())
    }

    /// With the content of the item's preview already built, as `ItemCellContentCache` keeps it.
    init(item: Item, context: ItemCellContext, content: Content) {
        self.init(item: item, context: context, strings: CardStrings(), content: content)
    }
}

nonisolated extension ItemCellModel {
    init(item: Item, context: ItemCellContext, strings: CardStrings, content: Content? = nil) {
        let content = content ?? Content(item.preview)
        let pinboardColor = Self.pinboardColor(of: item, in: context)
        let showsDate = switch context.collection {
        case .history, .picks: true
        case .pinboard: false
        case .search: pinboardColor == nil
        }

        self.init(
            id: item.id,
            // The preview is what the card can draw, so it decides the card; the item's type
            // still names it. They only differ while a preview is missing or out of date.
            type: content.itemType,
            customTitle: item.title,
            typeName: strings.typeName(for: item.type, fileCount: content.fileCount),
            // An item that has left the history has no "last used" date. A pinboard shows no
            // dates; a search result falls back to when the item was made.
            date: item.timestamp ?? item.createdAt,
            showsDate: showsDate,
            sourceApplication: item.sourceApplication.map(SourceApplication.init),
            pinboardColor: pinboardColor,
            quickPasteIndex: context.quickPasteIndex,
            content: content
        )
    }

    /// An item on a pinboard the caller did not supply still looks pinned, in the neutral colour.
    private static func pinboardColor(of item: Item, in context: ItemCellContext) -> PinboardColor? {
        guard let listID = item.listID, listID != .clipboard else { return nil }
        guard case .pinboard(let color) = context.pinboard?.attributes else { return .gray }
        return color
    }
}

nonisolated extension ItemCellModel.SourceApplication {
    init(_ application: PastoCore.SourceApplication) {
        self.init(
            name: application.name,
            iconData: application.iconData,
            color: application.colorCode == 0 ? nil : ColorCode(truncating: application.colorCode)
        )
    }
}

nonisolated extension ItemCellModel.Content {
    /// What a card draws for `preview`. Rich text is parsed, its colours summed up in the current
    /// appearance, and a link's image header read: build it in the appearance the card is drawn in.
    public init(_ preview: ItemPreview) {
        switch preview {
        case .text(let text):
            self = .text(ItemCellModel.Text(text))
        case .link(let link):
            self = .link(ItemCellModel.Link(
                url: link.url,
                title: link.title,
                iconData: link.iconData,
                image: link.imageData.flatMap(ItemCellModel.EncodedImage.init(data:))
            ))
        case .image(let image):
            self = .image(ItemCellModel.Image(width: image.width, height: image.height, thumbnailData: image.thumbnailData))
        case .color(let color):
            self = .color(ColorCode(truncating: color.colorCode))
        case .files(let files):
            self = .files(ItemCellModel.Files(paths: files.paths, thumbnailData: files.thumbnailData))
        case .unknown:
            self = .unknown
        }
    }

    var itemType: ItemType {
        switch self {
        case .text: .text
        case .link: .link
        case .image: .image
        case .color: .color
        case .files: .files
        case .unknown: .unknown
        }
    }

    /// How many files a file item holds; 1 for everything else, which never shows it.
    var fileCount: Int {
        if case .files(let files) = self { max(files.paths.count, 1) } else { 1 }
    }
}

nonisolated extension ItemCellModel.Text {
    /// The longest text a card lays out, in UTF-16 units.
    static let maximumLength = 20000

    init(_ preview: TextPreview) {
        let text = preview.richTextData.flatMap(Self.richText) ?? NSAttributedString(string: preview.text)
        self.init(attributedText: Self.clamped(text), characterCount: preview.characterCount)
    }

    /// RTF, or RTFD in its flat form. Anything else falls back to the plain text.
    private static func richText(from data: Data) -> NSAttributedString? {
        let text = NSAttributedString(rtf: data, documentAttributes: nil) ?? NSAttributedString(rtfd: data, documentAttributes: nil)
        guard let text, text.length > 0 else { return nil }
        return text
    }

    private static func clamped(_ text: NSAttributedString) -> NSAttributedString {
        guard text.length > maximumLength else { return text }
        // Never cut through a composed character.
        let range = (text.string as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: maximumLength))
        return text.attributedSubstring(from: range)
    }
}
