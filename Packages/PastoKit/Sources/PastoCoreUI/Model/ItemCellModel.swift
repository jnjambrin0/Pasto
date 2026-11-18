import Foundation
import PastoCore

/// Everything a card shows, and nothing it would have to fetch: cells are configured from this
/// value alone, so building it (off the main thread, if the caller wants) is where parsing and
/// lookups happen.
public nonisolated struct ItemCellModel: Sendable, Equatable, Identifiable {
    public var id: ItemID
    /// Which card draws the item. `unknown` when the item's preview does not match its type.
    public var type: ItemType
    /// The name the user gave the item, if any.
    public var customTitle: String?
    /// The localized name of the item's type, shown while there is no custom title.
    public var typeName: String
    public var date: Date
    /// False inside a pinboard, and in search results for items that are on a pinboard.
    public var showsDate: Bool
    public var sourceApplication: SourceApplication?
    /// The colour of the pinboard the item is on. A pinned item takes this colour for its header
    /// and shows no application icon.
    public var pinboardColor: PinboardColor?
    public var isTitleEditable: Bool
    /// 1...9 for the cards that quick paste can reach; see `quickPasteIndex(forCellAt:)`.
    public var quickPasteIndex: Int?
    public var content: Content

    /// The title in the header: the custom one, or the type's name.
    public var title: String {
        if let customTitle, !customTitle.isEmpty { customTitle } else { typeName }
    }

    public init(
        id: ItemID,
        type: ItemType,
        customTitle: String? = nil,
        typeName: String,
        date: Date,
        showsDate: Bool = true,
        sourceApplication: SourceApplication? = nil,
        pinboardColor: PinboardColor? = nil,
        isTitleEditable: Bool = true,
        quickPasteIndex: Int? = nil,
        content: Content
    ) {
        self.id = id
        self.type = type
        self.customTitle = customTitle
        self.typeName = typeName
        self.date = date
        self.showsDate = showsDate
        self.sourceApplication = sourceApplication
        self.pinboardColor = pinboardColor
        self.isTitleEditable = isTitleEditable
        self.quickPasteIndex = quickPasteIndex
        self.content = content
    }

    /// Only the first nine cards of the strip get a quick paste number.
    public static func quickPasteIndex(forCellAt index: Int) -> Int? {
        (0..<9).contains(index) ? index + 1 : nil
    }

    public struct SourceApplication: Sendable, Hashable {
        public var name: String
        /// Encoded image of the application's icon.
        public var iconData: Data?
        /// The colour of the header band; `nil` while it has not been computed.
        public var color: ColorCode?

        public init(name: String, iconData: Data? = nil, color: ColorCode? = nil) {
            self.name = name
            self.iconData = iconData
            self.color = color
        }
    }

    public enum Content: Sendable, Equatable {
        case text(Text)
        case link(Link)
        case image(Image)
        case color(ColorCode)
        case files(Files)
        case unknown
    }

    public struct Text: Sendable, Equatable {
        /// The text as it is drawn: with its own fonts and colours when it is rich text, without
        /// any attribute when it is plain.
        public var attributedText: NSAttributedString { storage.value }
        /// Length of the whole text, which the preview may have cut short.
        public var characterCount: Int
        /// What decides the card's background, worked out once here.
        let background: TextCardBackground.Summary
        private let storage: ImmutableAttributedString

        public init(attributedText: NSAttributedString, characterCount: Int) {
            storage = ImmutableAttributedString(attributedText)
            self.characterCount = characterCount
            background = TextCardBackground.summary(of: attributedText)
        }
    }

    public struct Link: Sendable, Hashable {
        public var url: URL
        /// The page's title, once its metadata has been fetched.
        public var title: String?
        /// Encoded image of the site's icon.
        public var iconData: Data?
        /// The page's preview image.
        public var image: EncodedImage?

        public init(url: URL, title: String? = nil, iconData: Data? = nil, image: EncodedImage? = nil) {
            self.url = url
            self.title = title
            self.iconData = iconData
            self.image = image
        }
    }

    public struct Image: Sendable, Hashable {
        /// Size of the full image in points, which the card states; the thumbnail is smaller.
        public var width: Int
        public var height: Int
        public var thumbnailData: Data?

        public init(width: Int, height: Int, thumbnailData: Data? = nil) {
            self.width = width
            self.height = height
            self.thumbnailData = thumbnailData
        }
    }

    public struct Files: Sendable, Hashable {
        public var paths: [String]
        /// Encoded thumbnail of the file, used when there is exactly one.
        public var thumbnailData: Data?

        public init(paths: [String], thumbnailData: Data? = nil) {
            self.paths = paths
            self.thumbnailData = thumbnailData
        }
    }

    /// An encoded image together with its size, so that a card can decide how to lay it out
    /// before it has been decoded.
    public struct EncodedImage: Sendable, Hashable {
        public var data: Data
        public var pixelWidth: Int
        public var pixelHeight: Int

        public init(data: Data, pixelWidth: Int, pixelHeight: Int) {
            self.data = data
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }

        /// Reads the size from the image's header, without decoding it. `nil` if `data` is not an image.
        public init?(data: Data) {
            guard let size = ImageDecoder.pixelSize(of: data) else { return nil }
            self.init(data: data, pixelWidth: size.width, pixelHeight: size.height)
        }

        var isSquare: Bool { pixelWidth == pixelHeight }
    }
}

/// An attributed string that is certain not to change, which is what makes it safe to hand from
/// the thread that builds a model to the main thread that draws it.
private nonisolated struct ImmutableAttributedString: @unchecked Sendable, Equatable {
    let value: NSAttributedString

    init(_ text: NSAttributedString) {
        // Copying an immutable string is free; copying a mutable one freezes it.
        value = text.copy() as? NSAttributedString ?? NSAttributedString(attributedString: text)
    }
}
