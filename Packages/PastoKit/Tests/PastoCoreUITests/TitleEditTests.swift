import Testing
@testable import PastoCoreUI

/// What confirming an edit of a card's title amounts to.
@Suite struct TitleEditTests {
    private func edit(_ typed: String, title: String? = nil) -> TitleEdit {
        TitleEdit(typed: typed, customTitle: title, typeName: "Text")
    }

    @Test func confirmingWhatWasShownWritesNothing() {
        #expect(edit("Text") == .unchanged)
        #expect(edit("Notes", title: "Notes") == .unchanged)
        // An empty stored title shows the type's name, like no title.
        #expect(edit("Text", title: "") == .unchanged)
    }

    @Test func aNewTitleIsTrimmed() {
        #expect(edit("  Shopping list\n") == .rename("Shopping list"))
        #expect(edit("Later", title: "Notes") == .rename("Later"))
    }

    @Test func theComparisonComesBeforeTheTrim() {
        // A trailing space is a change, and what gets written is the same title, trimmed.
        #expect(edit("Notes ", title: "Notes") == .rename("Notes"))
        // Typed over the type's name, it becomes a title of the item's own.
        #expect(edit("Text ") == .rename("Text"))
    }

    @Test func blankTakesTheTitleAway() {
        #expect(edit("", title: "Notes") == .rename(nil))
        #expect(edit("   ", title: "Notes") == .rename(nil))
    }

    @Test func blankOverNoTitleWritesNothing() {
        #expect(edit("") == .unchanged)
        #expect(edit("  ") == .unchanged)
    }
}
