import AppKit
import Carbon.HIToolbox
import Foundation
@testable import PastoMainPanel
import Testing

struct PanelGuideTests {
    private typealias Mark = PanelGuide.Mark
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let everything: Set<Mark> = [.cards, .search, .pinboards, .suggestions, .more]

    // MARK: - The tour

    @Test func theTourGoesInOrderAndEnds() {
        var guide = PanelGuide()

        #expect(guide.panelDidOpen(available: everything, at: now) == .cards)
        #expect(guide.next(available: everything, at: now) == .search)
        #expect(guide.next(available: everything, at: now) == .pinboards)
        #expect(guide.next(available: everything, at: now) == .suggestions)
        #expect(guide.next(available: everything, at: now) == .more)
        #expect(guide.next(available: everything, at: now) == nil)
        #expect(guide.seen == everything)
        #expect(guide.panelDidOpen(available: everything, at: now) == nil)
    }

    /// A new user's history is empty: the tour goes without the cards and shows them once there
    /// are some; without suggestions on this Mac, it never mentions them.
    @Test func stepsWhoseElementIsNotThereWait() {
        var guide = PanelGuide()
        let withoutCards: Set<Mark> = [.search, .pinboards, .more]

        #expect(guide.panelDidOpen(available: withoutCards, at: now) == .search)
        #expect(guide.next(available: withoutCards, at: now) == .pinboards)
        #expect(guide.next(available: withoutCards, at: now) == .more)
        #expect(guide.next(available: withoutCards, at: now) == nil)
        guide.panelWillClose(at: now)

        #expect(guide.panelDidOpen(available: withoutCards.union([.cards]), at: now) == .cards)
        #expect(guide.next(available: withoutCards.union([.cards]), at: now) == nil)
    }

    @Test func skipEndsTheWholeTour() {
        var guide = PanelGuide()
        _ = guide.panelDidOpen(available: everything, at: now)

        guide.skip()

        #expect(guide.current == nil)
        #expect(guide.seen.isSuperset(of: Mark.tour))
        #expect(guide.panelDidOpen(available: everything, at: now) == nil)
    }

    @Test func stepsCountTheElementsOnScreen() {
        let guide = PanelGuide()

        let full = guide.step(of: .search, available: everything)
        let short = guide.step(of: .search, available: [.search, .pinboards, .more])

        #expect(full?.number == 2 && full?.count == 5)
        #expect(short?.number == 1 && short?.count == 3)
        #expect(guide.step(of: .suggestionsFirstUse, available: everything) == nil)
    }

    @Test func theLastUnseenStepSaysDone() {
        var guide = PanelGuide(seen: [.pinboards, .suggestions, .more])
        _ = guide.panelDidOpen(available: everything, at: now)

        #expect(!guide.isLastStep(.cards, available: everything))
        #expect(guide.isLastStep(.search, available: everything))
    }

    // MARK: - Using the panel

    /// Anything done in the panel puts the mark away as seen, and the rest waits for the next
    /// opening.
    @Test func usingThePanelSetsTheTourAside() {
        var guide = PanelGuide()
        _ = guide.panelDidOpen(available: everything, at: now)

        guide.userDidSomething(learnt: [])

        #expect(guide.current == nil)
        #expect(guide.seen == [.cards])
        #expect(!guide.canResumeTour(available: everything))
        guide.panelWillClose(at: now)
        #expect(guide.panelDidOpen(available: everything, at: now) == .search)
    }

    /// What the user did shows they know it: its step is never shown.
    @Test func whatTheUserDidIsSeen() {
        var guide = PanelGuide()
        _ = guide.panelDidOpen(available: everything, at: now)

        guide.userDidSomething(learnt: [.search, .pinboards])
        guide.panelWillClose(at: now)

        #expect(guide.panelDidOpen(available: everything, at: now) == .suggestions)
    }

    @Test func closingThePanelCountsAMarkAsSeenOnlyOnceRead() {
        var quick = PanelGuide()
        _ = quick.panelDidOpen(available: everything, at: now)
        quick.panelWillClose(at: now.addingTimeInterval(PanelGuide.minimumReadingTime / 2))

        var read = PanelGuide()
        _ = read.panelDidOpen(available: everything, at: now)
        read.panelWillClose(at: now.addingTimeInterval(PanelGuide.minimumReadingTime))

        #expect(quick.seen.isEmpty)
        #expect(quick.panelDidOpen(available: everything, at: now) == .cards)
        #expect(read.seen == [.cards])
        #expect(read.panelDidOpen(available: everything, at: now) == .search)
    }

    // MARK: - Suggestions

    @Test func suggestionsExplainThemselvesTheFirstTimeOnly() {
        var guide = PanelGuide()
        _ = guide.panelDidOpen(available: everything, at: now)

        #expect(guide.suggestionsDidTurnOn(at: now) == .suggestionsFirstUse)
        #expect(guide.seen.isSuperset(of: [.cards, .suggestions]))
        #expect(guide.next(available: everything, at: now) == nil)
        #expect(guide.seen.contains(.suggestionsFirstUse))
        #expect(guide.suggestionsDidTurnOn(at: now) == nil)
    }

    // MARK: - Show Tips

    @Test func replayShowsEverythingAgain() {
        var guide = PanelGuide(seen: Set(Mark.allCases))

        guide.replay()

        #expect(guide.seen.isEmpty)
        #expect(guide.panelDidOpen(available: everything, at: now) == .cards)
    }

    // MARK: - Keys

    private func learnt(
        _ keyCode: Int,
        _ modifiers: NSEvent.ModifierFlags = [],
        _ characters: String? = nil,
        quickPaste: NSEvent.ModifierFlags = .command
    ) -> Set<Mark> {
        PanelGuide.learnt(
            byKey: UInt16(keyCode),
            modifiers: modifiers,
            characters: characters,
            quickPasteModifiers: quickPaste,
            tabShortcuts: [(kVK_LeftArrow, .command), (kVK_RightArrow, .command)]
        )
    }

    @Test func keysThatUseTheCards() {
        #expect(learnt(kVK_Return) == [.cards])
        #expect(learnt(kVK_ANSI_KeypadEnter) == [.cards])
        #expect(learnt(kVK_Space, [], " ") == [.cards])
        #expect(learnt(kVK_ANSI_3, .command, "3") == [.cards])
        #expect(learnt(kVK_ANSI_3, .option, "3", quickPaste: .option) == [.cards])
    }

    @Test func keysThatSearch() {
        #expect(learnt(kVK_ANSI_F, .command, "f") == [.search])
        #expect(learnt(kVK_ANSI_A, [], "a") == [.search])
        #expect(learnt(kVK_ANSI_A, .shift, "A") == [.search])
    }

    @Test func keysThatMoveBetweenPinboards() {
        #expect(learnt(kVK_RightArrow, .command) == [.pinboards])
        #expect(learnt(kVK_ANSI_N, [.command, .shift], "n") == [.pinboards])
    }

    @Test func otherKeysTeachNothing() {
        #expect(learnt(kVK_RightArrow).isEmpty)
        #expect(learnt(kVK_Escape).isEmpty)
        #expect(learnt(kVK_ANSI_C, .command, "c").isEmpty)
        // A digit with a modifier other than quick paste's.
        #expect(learnt(kVK_ANSI_3, .control, "3").isEmpty)
    }
}
