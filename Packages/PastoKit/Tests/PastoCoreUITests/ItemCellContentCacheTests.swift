import AppKit
import PastoCore
import Testing
@testable import PastoCoreUI

@MainActor
@Suite struct ItemCellContentCacheTests {
    let text = ItemPreview.text(TextPreview(text: "hello", characterCount: 5))

    func content(_ cache: ItemCellContentCache, _ preview: ItemPreview, _ appearance: NSAppearance.Name = .darkAqua, builds: inout Int) -> ItemCellModel.Content {
        cache.content(for: preview, in: appearance) {
            builds += 1
            return ItemCellModel.Content(preview)
        }
    }

    @Test func aTextIsBuiltOncePerAppearance() {
        let cache = ItemCellContentCache()
        var builds = 0
        let first = content(cache, text, builds: &builds)
        let again = content(cache, text, builds: &builds)
        #expect(builds == 1)
        #expect(first == again)
        _ = content(cache, text, .aqua, builds: &builds)
        #expect(builds == 2)
    }

    @Test func aChangedPreviewIsBuiltAfresh() {
        let cache = ItemCellContentCache()
        var builds = 0
        _ = content(cache, text, builds: &builds)
        _ = content(cache, .text(TextPreview(text: "hello!", characterCount: 6)), builds: &builds)
        #expect(builds == 2)
    }

    @Test func cheapKindsAreNotKept() {
        let cache = ItemCellContentCache()
        var builds = 0
        let color = ItemPreview.color(ColorPreview(colorCode: 0xFF0000))
        _ = content(cache, color, builds: &builds)
        _ = content(cache, color, builds: &builds)
        #expect(builds == 2)
        #expect(ItemCellContentCache.cost(of: .image(ImagePreview(width: 1, height: 1, byteCount: 1))) == nil)
        #expect(ItemCellContentCache.cost(of: .unknown) == nil)
    }

    @Test func costIsTwiceTheBytesDecoded() {
        #expect(ItemCellContentCache.cost(of: text) == 10)
        let rich = ItemPreview.text(TextPreview(text: "hello", characterCount: 5, richTextData: Data(count: 300)))
        #expect(ItemCellContentCache.cost(of: rich) == 600)
        let link = ItemPreview.link(LinkPreview(url: URL(string: "https://a.b")!, title: "T", imageData: Data(count: 100)))
        #expect(ItemCellContentCache.cost(of: link) == 2 * (11 + 1 + 100))
    }

    @Test func entriesOverHalfTheLimitAreNotKept() {
        let cache = ItemCellContentCache()
        var builds = 0
        let huge = ItemPreview.text(TextPreview(text: String(repeating: "a", count: ItemCellContentCache.totalCostLimit / 4 + 1), characterCount: 1))
        _ = content(cache, huge, builds: &builds)
        _ = content(cache, huge, builds: &builds)
        #expect(builds == 2)
    }
}
