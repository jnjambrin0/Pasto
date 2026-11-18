import Foundation

/// One clipboard entry of a deterministic seed set.
public struct SeedItem: Sendable {
    public enum Payload: Sendable {
        case text(String)
        case richText(plain: String, rtf: String, html: String)
        case url(String)
        case image(SeedImage)
        case files([FixtureFile])
    }

    /// Stable across runs; use it to refer to the item in measurements.
    public let id: String
    public let summary: String
    public let payload: Payload

    /// Pasteboard types the item is written with.
    public var types: [String] {
        switch payload {
        case .text: ["public.utf8-plain-text"]
        case .richText: ["public.rtf", "public.html", "public.utf8-plain-text"]
        case .url: ["public.url", "public.utf8-plain-text"]
        case .image: ["public.png"]
        case .files(let files): files.map { _ in "public.file-url" }
        }
    }
}

public enum SeedSet: String, Sendable {
    /// One item of each main kind: text, rich text, link, colour, image, file.
    case basic
    /// Every item, in a fixed order.
    case full

    public var items: [SeedItem] {
        switch self {
        case .full: Self.catalogue
        case .basic: Self.catalogue.filter { Self.basicIDs.contains($0.id) }
        }
    }

    private static let basicIDs: Set<String> = [
        "text-short", "text-multiline", "rich-text", "url-simple", "color-hex", "image-gradient", "file-single",
    ]

    private static let catalogue: [SeedItem] = [
        SeedItem(id: "text-short", summary: "short plain text", payload: .text("ProbeKit seed: short plain text")),
        SeedItem(
            id: "text-multiline", summary: "three lines of plain text",
            payload: .text("ProbeKit seed: multi-line text\nSecond line with\ta tab\nThird and last line")
        ),
        SeedItem(id: "text-long", summary: "3 000 characters of lorem ipsum", payload: .text(loremIpsum(length: 3000))),
        SeedItem(
            id: "rich-text", summary: "rich text as RTF, HTML and plain text",
            payload: .richText(
                plain: "ProbeKit seed: rich text with bold, italic and orange words.",
                rtf: #"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Helvetica;}}{\colortbl;\red255\green149\blue0;}"#
                    + #"\f0\fs28 ProbeKit seed: rich text with {\b bold}, {\i italic} and {\cf1 orange} words.}"#,
                html: #"<meta charset="utf-8"><p style="font-family: Helvetica; font-size: 14px">ProbeKit seed: rich text with "#
                    + #"<b>bold</b>, <i>italic</i> and <span style="color: #FF9500">orange</span> words.</p>"#
            )
        ),
        SeedItem(id: "url-simple", summary: "web link", payload: .url("https://www.apple.com/macos/")),
        SeedItem(
            id: "url-query", summary: "web link with a path and a query",
            payload: .url("https://developer.apple.com/documentation/appkit/nspasteboard?language=swift&probe=seed")
        ),
        SeedItem(id: "color-hex", summary: "hex colour with a hash", payload: .text("#FF9500")),
        SeedItem(id: "color-bare", summary: "hex colour without a hash", payload: .text("34C759")),
        SeedItem(
            id: "code-snippet", summary: "Swift code snippet",
            payload: .text("""
            func fibonacci(_ n: Int) -> Int {
                guard n > 1 else { return n }
                return fibonacci(n - 1) + fibonacci(n - 2)
            }

            print((0..<10).map(fibonacci))
            """)
        ),
        SeedItem(
            id: "text-emoji-cjk", summary: "text with emoji and CJK",
            payload: .text("ProbeKit seed: emoji 🎨📋✨👩‍💻 · 日本語のテキスト · 中文文本 · 한국어 텍스트")
        ),
        SeedItem(id: "image-gradient", summary: "640x400 PNG gradient with a label", payload: .image(.gradient)),
        SeedItem(id: "image-transparent", summary: "96x96 PNG with a transparent background", payload: .image(.transparentBadge)),
        SeedItem(id: "file-single", summary: "one text file", payload: .files([.text])),
        SeedItem(id: "files-multi", summary: "a text file, a PDF and a PNG selected together", payload: .files(FixtureFile.allCases)),
    ]

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
