import Foundation
import PastoCore
import Testing
@testable import PastoMainPanel

/// The entries of a card's context menu, the lists "Show in …" offers and the pin submenu.
@Suite struct ItemMenuContentTests {
    private static let board = ListID(rawValue: "board")

    private func item(_ id: String, inHistory: Bool = true, on pinboard: ListID? = nil) -> Item {
        Item(
            id: ItemID(rawValue: id), type: .text, preview: .text(TextPreview(text: id, characterCount: id.count)),
            timestamp: inHistory ? Date(timeIntervalSinceReferenceDate: 0) : nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 0), listID: pinboard
        )
    }

    // MARK: - Entries

    @Test func aPlainItemGetsTheEntriesThatAreAlwaysThere() {
        #expect(ItemMenuContent().entries == [
            .paste(applicationName: nil), .pasteAsPlainText, .copy, .separator,
            .rename, .delete, .separator,
            .pin, .separator,
            .share,
        ])
    }

    @Test func everythingOnInMenuOrder() {
        var content = ItemMenuContent()
        content.canOpen = true
        content.openingApplicationName = "Preview"
        content.isFiles = true
        content.showInLists = [.clipboard, Self.board]
        content.pasteTargetName = "Notes"
        content.offersShowIn = true
        content.offersCreateStack = true
        content.offersEdit = true
        content.offersWritingTools = true
        content.offersPreview = true

        #expect(content.entries == [
            .open(applicationName: "Preview"), .revealInFinder, .showIn(.clipboard), .showIn(Self.board), .separator,
            .paste(applicationName: "Notes"), .pasteAsPlainText, .copy, .createStack, .separator,
            .edit, .writingTools, .rename, .delete, .separator,
            .pin, .separator,
            .preview, .share,
        ])
    }

    @Test func theFirstGroupBringsItsSeparatorOnlyWhenItHasAnEntry() {
        var content = ItemMenuContent()
        content.isFiles = true

        #expect(content.entries.prefix(3) == [.revealInFinder, .separator, .paste(applicationName: nil)])
    }

    @Test func alwaysPastingAsPlainTextLeavesOnePasteEntry() {
        var content = ItemMenuContent()
        content.isAlwaysPlainText = true

        #expect(!content.entries.contains(.pasteAsPlainText))
        #expect(content.entries.first == .paste(applicationName: nil))
    }

    @Test func showInNeedsSomebodyToShowTheList() {
        var content = ItemMenuContent()
        content.showInLists = [.clipboard]

        #expect(!content.entries.contains(.showIn(.clipboard)))
    }

    // MARK: - Show in

    @Test func showInOffersTheOtherListsTheItemIsIn() {
        let pinned = item("a", on: Self.board)

        // In the history: only its pinboard. On its pinboard: only the history.
        #expect(ShowInLists.lists(for: [pinned], shownList: .clipboard) == [Self.board])
        #expect(ShowInLists.lists(for: [pinned], shownList: Self.board) == [.clipboard])
        // Anywhere else, the history first; search results are in no list, so they offer both.
        #expect(ShowInLists.lists(for: [pinned], shownList: ListID(rawValue: "other")) == [.clipboard, Self.board])
        #expect(ShowInLists.lists(for: [pinned], shownList: nil) == [.clipboard, Self.board])
    }

    @Test func showInSkipsTheHistoryForAnItemThatLeftIt() {
        let pinnedOnly = item("a", inHistory: false, on: Self.board)

        #expect(ShowInLists.lists(for: [pinnedOnly], shownList: Self.board).isEmpty)
    }

    @Test func showInNeedsExactlyOneSelectedItem() {
        let pinned = item("a", on: Self.board)

        #expect(ShowInLists.lists(for: [], shownList: .clipboard).isEmpty)
        #expect(ShowInLists.lists(for: [pinned, item("b", on: Self.board)], shownList: .clipboard).isEmpty)
    }

    // MARK: - Pin submenu

    @Test func aPinboardIsCheckedByHowMuchOfTheSelectionIsOnIt() {
        let selection = [item("a", on: Self.board), item("b")]

        #expect(PinMenu.Membership(of: Self.board, in: selection) == .some)
        #expect(PinMenu.Membership(of: Self.board, in: [selection[0]]) == .all)
        #expect(PinMenu.Membership(of: Self.board, in: [selection[1]]) == .none)
        #expect(PinMenu.Membership(of: Self.board, in: []) == .none)
    }

    // MARK: - Editable content

    @Test func filesAndUnknownContentCannotBeEdited() {
        #expect(ItemType.allCases.filter(\.hasEditableContent) == [.image, .color, .link, .text])
    }
}
