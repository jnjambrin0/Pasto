import Foundation
import PastoCore
import PastoCoreUI

/// The fixed set of cards the gallery renders: the items `pastoprobe seed --set full` copies, plus
/// a few states the seed cannot produce (a link without metadata, a dark colour, an unknown item,
/// a pinned item).
struct SampleCard {
    let name: String
    let model: ItemCellModel

    /// The moment the cards are rendered at; every item was copied twelve minutes earlier.
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// The cards in strip order: the first nine carry a quick paste number.
    static let all: [SampleCard] = cards.enumerated().map { index, sample in
        var model = sample.model
        model.quickPasteIndex = ItemCellModel.quickPasteIndex(forCellAt: index)
        return SampleCard(name: sample.name, model: model)
    }

    private static let cards: [SampleCard] = [
        text("text-short", "ProbeKit seed: short plain text"),
        text("text-multiline", "ProbeKit seed: multi-line text\nSecond line with\ta tab\nThird and last line"),
        text("text-long", loremIpsum(length: 3000)),
        richText,
        link(
            "url-simple", "https://www.apple.com/macos/", title: "macOS",
            imageData: SampleImages.linkPreview
        ),
        link(
            "url-query", "https://developer.apple.com/documentation/appkit/nspasteboard?language=swift&probe=seed",
            title: "NSPasteboard | Apple Developer Documentation", iconData: SampleImages.siteIcon
        ),
        link("url-pending", "https://example.com/a/page/whose/metadata/has/not/arrived/yet"),
        card("color-hex", .color, .color(ColorPreview(colorCode: 0xFF9500))),
        card("color-bare", .color, .color(ColorPreview(colorCode: 0x34C759))),
        card("color-dark", .color, .color(ColorPreview(colorCode: 0x102040))),
        text("code-snippet", """
        func fibonacci(_ n: Int) -> Int {
            guard n > 1 else { return n }
            return fibonacci(n - 1) + fibonacci(n - 2)
        }

        print((0..<10).map(fibonacci))
        """),
        text("text-emoji-cjk", "ProbeKit seed: emoji 🎨📋✨👩‍💻 · 日本語のテキスト · 中文文本 · 한국어 텍스트"),
        card("image-gradient", .image, .image(ImagePreview(
            width: 640, height: 400, byteCount: SampleImages.gradient.count, thumbnailData: SampleImages.gradient
        ))),
        card("image-transparent", .image, .image(ImagePreview(
            width: 96, height: 96, byteCount: SampleImages.transparentBadge.count,
            thumbnailData: SampleImages.transparentBadge
        ))),
        fileSingle,
        card("files-multi", .files, .files(FilesPreview(paths: [
            fixturesDirectory + "probekit-note.txt",
            fixturesDirectory + "probekit-document.pdf",
            fixturesDirectory + "probekit-picture.png",
        ]))),
        card("unknown", .unknown, .unknown),
        pinnedText,
    ]

    // MARK: - Builders

    private static let fixturesDirectory = "/Users/example/Documents/"

    private static let sourceApplication = SourceApplication(
        bundleIdentifier: "com.example.terminal",
        name: "Terminal",
        // A header colour as capture derives it from an app's icon (a dark terminal's).
        colorCode: 0xFF18_0119,
        iconData: SampleImages.applicationIcon
    )

    private static func card(
        _ name: String,
        _ type: ItemType,
        _ preview: ItemPreview,
        context: ItemCellContext = ItemCellContext(collection: .history),
        listID: ListID? = nil
    ) -> SampleCard {
        let date = now.addingTimeInterval(-12 * 60)
        let item = Item(
            id: ItemID(rawValue: name), type: type, preview: preview, timestamp: date, createdAt: date,
            listID: listID, sourceApplication: sourceApplication
        )
        return SampleCard(name: name, model: ItemCellModel(item: item, context: context))
    }

    private static func text(_ name: String, _ text: String) -> SampleCard {
        // Captions count UTF-16 units, as the capture pipeline does.
        card(name, .text, .text(TextPreview(text: text, characterCount: text.utf16.count)))
    }

    private static func link(
        _ name: String, _ url: String, title: String? = nil, iconData: Data? = nil, imageData: Data? = nil
    ) -> SampleCard {
        guard let url = URL(string: url) else { fatalError("bad sample URL \(url)") }
        return card(name, .link, .link(LinkPreview(url: url, title: title, iconData: iconData, imageData: imageData)))
    }

    private static let richText: SampleCard = {
        let plain = "ProbeKit seed: rich text with bold, italic and orange words."
        let rtf = #"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Helvetica;}}{\colortbl;\red255\green149\blue0;}"#
            + #"\f0\fs28 ProbeKit seed: rich text with {\b bold}, {\i italic} and {\cf1 orange} words.}"#
        return card("rich-text", .text, .text(TextPreview(text: plain, characterCount: plain.utf16.count, richTextData: Data(rtf.utf8))))
    }()

    /// The capture pipeline does not put the file's thumbnail in the preview yet, so it is
    /// added to the model directly.
    private static let fileSingle: SampleCard = {
        let paths = [fixturesDirectory + "probekit-note.txt"]
        var model = card("file-single", .files, .files(FilesPreview(paths: paths))).model
        model.content = .files(ItemCellModel.Files(paths: paths, thumbnailData: SampleImages.fileThumbnail))
        return SampleCard(name: "file-single", model: model)
    }()

    private static let pinnedText: SampleCard = {
        let pinboard = ClipList(
            id: ListID(rawValue: "sample-pinboard"), name: "Samples", type: .pinboard,
            attributes: .pinboard(color: .red), index: 1
        )
        let text = "A text item kept on a red pinboard"
        return card(
            "pinned-text", .text, .text(TextPreview(text: text, characterCount: text.utf16.count)),
            context: ItemCellContext(collection: .pinboard, pinboard: pinboard), listID: pinboard.id
        )
    }()

    private static func loremIpsum(length: Int) -> String {
        let paragraph = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et \
        dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip \
        ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu \
        fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt \
        mollit anim id est laborum.
        """
        var text = paragraph
        while text.count < length { text += "\n\n" + paragraph }
        return String(text.prefix(length))
    }
}
