import Foundation
import PastoCore
import Testing
@testable import PastoPreview

/// The small rules around editing: what the link editor accepts, what confirming a title does,
/// which items have an editor, and the counts under a text.
@Suite struct EditingRulesTests {
    // MARK: Link input

    @Test func anAddressWithASchemeIsTakenAsItIs() {
        #expect(LinkInput.url(from: "https://example.com/a?b=c")?.absoluteString == "https://example.com/a?b=c")
        #expect(LinkInput.url(from: "ftp://example.com")?.absoluteString == "ftp://example.com")
        #expect(LinkInput.url(from: "mailto:someone@example.com")?.absoluteString == "mailto:someone@example.com")
    }

    @Test func anAddressWithoutASchemeBecomesSecureWeb() {
        #expect(LinkInput.url(from: "example.com/path")?.absoluteString == "https://example.com/path")
    }

    @Test func nothingIsNotAnAddress() {
        #expect(LinkInput.url(from: "") == nil)
    }

    /// Return in the editor adds a line break; after a path it is escaped and Save stays
    /// enabled.
    @Test func aLineBreakAfterAPathStillMakesAnAddress() {
        #expect(LinkInput.url(from: "https://example.com/path\n")?.absoluteString == "https://example.com/path%0A")
    }

    // MARK: Title

    @Test func aNewTitleIsTrimmed() {
        #expect(TitleEdit(text: "  Recipe \n", currentTitle: nil) == .set("Recipe"))
        #expect(TitleEdit(text: "Recipe", currentTitle: "Old") == .set("Recipe"))
    }

    @Test func theSameTitleWritesNothing() {
        #expect(TitleEdit(text: "Recipe", currentTitle: "Recipe") == .unchanged)
        #expect(TitleEdit(text: " Recipe ", currentTitle: "Recipe") == .unchanged)
        #expect(TitleEdit(text: "   ", currentTitle: nil) == .unchanged)
    }

    @Test func anEmptyTitleRemovesTheItemsOwn() {
        #expect(TitleEdit(text: "", currentTitle: "Recipe") == .set(nil))
        #expect(TitleEdit(text: " \n", currentTitle: "Recipe") == .set(nil))
    }

    // MARK: Content kind

    private func item(_ type: ItemType, _ preview: ItemPreview = .unknown) -> Item {
        let date = Date(timeIntervalSince1970: 0)
        return Item(id: ItemID(rawValue: "item"), type: type, preview: preview, timestamp: date, createdAt: date)
    }

    @Test func eachTypeHasItsContent() throws {
        let url = try #require(URL(string: "https://example.com"))
        #expect(ItemContentKind(item: item(.text)) == .text)
        #expect(ItemContentKind(item: item(.link, .link(LinkPreview(url: url)))) == .link(url))
        #expect(ItemContentKind(item: item(.image)) == .image)
        #expect(ItemContentKind(item: item(.color)) == .color)
        #expect(ItemContentKind(item: item(.files)) == .files)
        #expect(ItemContentKind(item: item(.unknown)) == .unknown)
    }

    @Test func aLinkWithoutAnAddressIsShownAsText() {
        let preview = ItemPreview.text(TextPreview(text: "not quite a link", characterCount: 16))
        #expect(ItemContentKind(item: item(.link, preview)) == .text)
    }

    @Test func filesAndUnknownContentCannotBeEdited() throws {
        let url = try #require(URL(string: "https://example.com"))
        let editable: [ItemContentKind] = [.text, .link(url), .image, .color]
        #expect(editable.filter { !$0.isEditable }.isEmpty)
        #expect(!ItemContentKind.files.isEditable)
        #expect(!ItemContentKind.unknown.isEditable)
    }

    // MARK: Statistics

    /// Characters, words and lines, in that order.
    private func counts(of text: String) -> [Int] {
        let statistics = TextStatistics(of: text)
        return [statistics.characters, statistics.words, statistics.lines]
    }

    @Test func anEmptyTextHasOneLineAndNothingElse() {
        #expect(counts(of: "") == [0, 0, 1])
    }

    @Test func countsCharactersWordsAndLines() {
        #expect(counts(of: "hello world") == [11, 2, 1])
        #expect(counts(of: "  spaced   out  ") == [16, 2, 1])
        #expect(counts(of: "one\ttwo") == [7, 2, 1])
    }

    @Test func aLineBreakEndsALineButNotAWord() {
        #expect(counts(of: "one two\nthree four") == [18, 3, 2])
        #expect(counts(of: "a\n\nb\n") == [5, 1, 4])
    }

    @Test func charactersAreWhatTheUserSees() {
        #expect(counts(of: "👍🏽é")[0] == 2)
    }
}
