import AppKit
import PastoCore
import Testing
@testable import PastoPreview

/// How the content is shown and what it offers: the colours given to text without its own, and
/// when there is something to share.
@Suite struct ContentRulesTests {
    // MARK: Text colours

    private let primary = NSColor.systemPurple
    private let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
    private let black = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)

    private func color(of text: NSAttributedString, at index: Int = 0) -> NSColor? {
        text.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    @Test func aRunWithAColourOfItsOwnKeepsIt() {
        let text = NSAttributedString(string: "a", attributes: [.foregroundColor: NSColor.red, .backgroundColor: black])
        #expect(color(of: TextRecoloring.readable(text, on: white, primary: primary)) == .red)
    }

    @Test func aRunWithNeitherColourNorBackgroundTakesThePrimaryColour() {
        let text = NSAttributedString(string: "a")
        #expect(color(of: TextRecoloring.readable(text, on: black, primary: primary)) == primary)
    }

    @Test func aRunOnABackgroundOfItsOwnIsBlackOrWhiteByItsLightness() {
        let text = NSMutableAttributedString(string: "ab")
        text.addAttribute(.backgroundColor, value: NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 1), range: NSRange(location: 0, length: 1))
        text.addAttribute(.backgroundColor, value: NSColor(deviceRed: 0, green: 0, blue: 0.8, alpha: 1), range: NSRange(location: 1, length: 1))
        let readable = TextRecoloring.readable(text, on: white, primary: primary)
        #expect(color(of: readable, at: 0) == .black)
        #expect(color(of: readable, at: 1) == .white)
    }

    @Test func aTranslucentBackgroundIsJudgedOverThePreviews() {
        // Black at 40 % over white is 0.6 light, above the threshold; at 50 % it is 0.5, below.
        let lighter = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0.4)
        let darker = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0.5)
        #expect(TextRecoloring.contrastingColor(on: lighter, over: white) == .black)
        #expect(TextRecoloring.contrastingColor(on: darker, over: white) == .white)
        #expect(TextRecoloring.contrastingColor(on: lighter, over: black) == .white)
    }

    // MARK: Sharing

    private func snapshot(_ type: String, _ data: Data = Data("x".utf8)) -> PasteboardItemSnapshot {
        PasteboardItemSnapshot(types: [type], dataByType: [type: data])
    }

    private func canShare(_ preview: ItemPreview, _ items: [PasteboardItemSnapshot] = [], reachable: Bool = true) -> Bool {
        ShareAvailability.canShare(preview, pasteboardItems: items, isReachable: { _ in reachable })
    }

    @Test func textAndColoursShareTheirString() {
        let text = ItemPreview.text(TextPreview(text: "x", characterCount: 1))
        #expect(canShare(text, [snapshot("public.utf8-plain-text")]))
        #expect(!canShare(text, [snapshot("public.rtf")]))
        #expect(canShare(.color(ColorPreview(colorCode: 0xFF0000)), [snapshot("public.utf8-plain-text")]))
    }

    @Test func aLinkSharesItsAddress() throws {
        let url = try #require(URL(string: "https://example.com"))
        #expect(canShare(.link(LinkPreview(url: url))))
    }

    @Test func anImageNeedsItsImageData() {
        let image = ItemPreview.image(ImagePreview(width: 1, height: 1, byteCount: 1))
        #expect(canShare(image, [snapshot("public.png")]))
        #expect(!canShare(image, [snapshot("public.utf8-plain-text")]))
    }

    @Test func filesAreSharedOnlyWhileEveryOneIsThere() {
        let files = ItemPreview.files(FilesPreview(paths: ["/a", "/b"]))
        #expect(canShare(files))
        #expect(!canShare(files, reachable: false))
        #expect(!canShare(.files(FilesPreview(paths: []))))
        let onlyFirst = ShareAvailability.canShare(files, pasteboardItems: [], isReachable: { $0 == "/a" })
        #expect(!onlyFirst)
    }

    @Test func unknownContentHasNothingToShare() {
        #expect(!canShare(.unknown, [snapshot("public.utf8-plain-text")]))
    }
}
