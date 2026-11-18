@testable import PastoOnboarding
import PastoUI
import Testing

struct NoticeCatalogTests {
    @Test func theEndOfOnboardingLeavesACardForEachThingStillOff() {
        let cards = NoticeCatalog.cardsAfterOnboarding(isLoginItemEnabled: false, isDirectPasteEnabled: false)

        #expect(cards.map(\.id) == ["openAtLogin", "enableDirectPaste"])
        #expect(cards.map(\.action.command) == [.enableOpenAtLogin, .enableDirectPaste])
    }

    @Test func whatIsAlreadyOnGetsNoCard() {
        #expect(NoticeCatalog.cardsAfterOnboarding(isLoginItemEnabled: true, isDirectPasteEnabled: true).isEmpty)
        #expect(
            NoticeCatalog.cardsAfterOnboarding(isLoginItemEnabled: true, isDirectPasteEnabled: false).map(\.id)
                == ["enableDirectPaste"]
        )
    }

    // MARK: Other clipboard managers

    @Test func otherClipboardManagersOpenGetACardNamingThemAfterTheRest() throws {
        let cards = NoticeCatalog.cardsAfterOnboarding(
            isLoginItemEnabled: false,
            isDirectPasteEnabled: true,
            otherClipboardManagers: ["Paste", "Maccy"]
        )

        #expect(cards.map(\.id) == ["openAtLogin", "otherClipboardManagers"])
        let card = try #require(cards.last)
        #expect(card.action.command == .acknowledgeOtherClipboardManagers)
        let description = try #require(card.description)
        #expect(description.contains("Paste"))
        #expect(description.contains("Maccy"))
    }

    @Test func noOtherClipboardManagerNoCard() {
        #expect(NoticeCatalog.otherClipboardManagers(named: []) == nil)
        #expect(
            NoticeCatalog.cardsAfterOnboarding(isLoginItemEnabled: true, isDirectPasteEnabled: true, otherClipboardManagers: [])
                .isEmpty
        )
    }

    @Test func thePasteboardAccessCardAsksForAccess() {
        #expect(NoticeCatalog.pasteboardAccess.action.command == .allowPasteboardAccess)
    }

    @Test func shortcutsInUseGetACardThatLeadsToTheShortcutSettings() throws {
        let card = try #require(NoticeCatalog.shortcutsTaken(["⇧⌘V", "⇧⌘C"]))

        #expect(card.id == NoticeCatalog.shortcutsTakenID)
        #expect(card.action.command == .openShortcutSettings)
        let description = try #require(card.description)
        #expect(description.contains("⇧⌘V") && description.contains("⇧⌘C"))
        #expect(NoticeCatalog.shortcutsTaken([]) == nil)
    }

    @Test func theCardAboutFailedSavesLeadsToTheStorageSettings() {
        #expect(NoticeCatalog.storeWriteFailure.action.command == .openStorageSettings)
    }
}

struct StoreWriteFailureStreakTests {
    @Test func theCardIsOwedFromTheThirdFailureInARow() {
        var streak = StoreWriteFailureStreak()

        #expect([streak.writeDidFail(), streak.writeDidFail(), streak.writeDidFail(), streak.writeDidFail()] == [false, false, true, true])
    }

    @Test func aSavedWriteStartsTheCountAgain() {
        var streak = StoreWriteFailureStreak()
        _ = streak.writeDidFail()
        _ = streak.writeDidFail()

        streak.writeDidSucceed()

        #expect([streak.writeDidFail(), streak.writeDidFail(), streak.writeDidFail()] == [false, false, true])
    }
}

struct PasteboardAccessReminderTests {
    /// What successive copies made in these conditions decide.
    private func answers(_ copies: [(isDenied: Bool, isPanelOpen: Bool, isModalWindowUp: Bool)]) -> [Bool] {
        var reminder = PasteboardAccessReminder()
        return copies.map { reminder.shouldAsk(isDenied: $0.isDenied, isPanelOpen: $0.isPanelOpen, isModalWindowUp: $0.isModalWindowUp) }
    }

    @Test func theWindowGoesUpOncePerLaunchAtMost() {
        let free = (isDenied: false, isPanelOpen: false, isModalWindowUp: false)

        #expect(answers([free, free, free]) == [true, false, false])
    }

    @Test func notOverThePanelNorAnotherModalWindowAndThenOnTheNextCopy() {
        let copies = [
            (isDenied: false, isPanelOpen: true, isModalWindowUp: false),
            (isDenied: false, isPanelOpen: false, isModalWindowUp: true),
            (isDenied: false, isPanelOpen: false, isModalWindowUp: false),
        ]

        #expect(answers(copies) == [false, false, true])
    }

    @Test func neverOnceTheUserDeniedAccess() {
        let denied = (isDenied: true, isPanelOpen: false, isModalWindowUp: false)

        #expect(answers([denied, denied]) == [false, false])
    }
}
