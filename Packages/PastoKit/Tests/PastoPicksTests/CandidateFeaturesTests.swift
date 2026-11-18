import Foundation
import PastoCore
@testable import PastoPicks
import Testing

struct CandidateFeaturesTests {
    private let mail = "com.example.mail"
    private let editor = "com.example.editor"
    private let browser = "com.example.browser"
    private let terminal = "com.example.terminal"

    @Test func theJournalWindowIsItsNewestEventsNewestFirst() {
        let journal = (0..<600).map { event("item-\($0)", from: mail, to: editor, at: $0) }
        let history = PasteHistory(journal: journal)
        #expect(history.events.count == PicksMetrics.journalWindow)
        #expect(history.events.first?.itemIdentifier.rawValue == "item-599")
        #expect(history.events.last?.itemIdentifier.rawValue == "item-100")
    }

    @Test func countsAndTheLatestSource() {
        let history = PasteHistory(journal: [
            event("a", from: mail, to: editor, at: 0),
            event("a", from: mail, to: terminal, at: 1),
            event("b", from: browser, to: editor, at: 2),
            event("c", from: mail, to: editor, at: 3),
        ])
        #expect(history.pasteCount(of: ItemID(rawValue: "a")) == 2)
        #expect(history.pasteCount(from: mail, into: editor) == 2)
        #expect(history.pasteCount(from: browser, into: terminal) == 0)
        #expect(history.latestPaste(into: editor)?.itemIdentifier.rawValue == "c")
        #expect(history.latestPaste(into: browser) == nil)
    }

    @Test func featuresOfTheCandidates() {
        let history = PasteHistory(journal: [
            event("a", from: mail, to: editor, at: 0),
            event("b", from: browser, to: editor, at: 1),
            event("a", from: mail, to: editor, at: 2),
        ])
        let candidates = [
            Candidate(id: ItemID(rawValue: "a"), type: .text, sourceAppBundleIdentifier: mail, itemClass: .message),
            Candidate(id: ItemID(rawValue: "x"), type: .link, sourceAppBundleIdentifier: browser, itemClass: .link),
            Candidate(id: ItemID(rawValue: "y"), type: .image, sourceAppBundleIdentifier: nil, itemClass: .unclassified),
        ]
        let features = CandidateFeatures.features(of: candidates, history: history, destination: editor)

        #expect(features.map(\.recencyRank) == [0, 1, 2])
        #expect(features.map(\.pasteCount) == [2, 0, 0])
        #expect(features.map(\.pairPasteCount) == [2, 1, 0])
        // The last paste into the editor came from the mail application.
        #expect(features.map(\.isSourceOfLatestPaste) == [true, false, false])
        #expect(features[1].itemType == .link)
        #expect(features[0].itemClass == .message)
    }

    @Test func beforeAnythingIsPastedThereTheFeaturesAreZeroAndFalse() {
        let history = PasteHistory(journal: [event("a", from: mail, to: editor, at: 0)])
        let candidates = [Candidate(id: ItemID(rawValue: "a"), type: .text, sourceAppBundleIdentifier: mail, itemClass: .unclassified)]
        let features = CandidateFeatures.features(of: candidates, history: history, destination: terminal)
        #expect(features[0].isSourceOfLatestPaste == false)
        #expect(features[0].pairPasteCount == 0)
        #expect(features[0].pasteCount == 1)
    }

    @Test func anItemFromNoKnownApplicationIsNotTheLatestSource() {
        let history = PasteHistory(journal: [event("a", from: nil, to: editor, at: 0)])
        let candidates = [Candidate(id: ItemID(rawValue: "b"), type: .text, sourceAppBundleIdentifier: nil, itemClass: .unclassified)]
        let features = CandidateFeatures.features(of: candidates, history: history, destination: editor)
        #expect(features[0].isSourceOfLatestPaste == false)
        #expect(features[0].pairPasteCount == 0)
    }

    @Test func pastesWithNoDestinationTeachOnlyHowOftenAnItemIsPasted() {
        // Pastes made from the panel outside the mode have no destination (the frontmost
        // application is Pasto itself when they are noted).
        let history = PasteHistory(journal: [
            PasteEvent(itemIdentifier: ItemID(rawValue: "a"), sourceAppBundleIdentifier: mail,
                       destinationAppBundleIdentifier: nil, timestamp: Date(timeIntervalSinceReferenceDate: 0)),
        ])
        let candidates = [Candidate(id: ItemID(rawValue: "a"), type: .text, sourceAppBundleIdentifier: mail, itemClass: .unclassified)]
        let features = CandidateFeatures.features(of: candidates, history: history, destination: editor)
        #expect(features[0].pasteCount == 1)
        #expect(features[0].pairPasteCount == 0)
        #expect(features[0].isSourceOfLatestPaste == false)
    }

    private func event(_ item: String, from source: String?, to destination: String, at second: Int) -> PasteEvent {
        PasteEvent(
            itemIdentifier: ItemID(rawValue: item),
            sourceAppBundleIdentifier: source,
            destinationAppBundleIdentifier: destination,
            timestamp: Date(timeIntervalSinceReferenceDate: TimeInterval(second))
        )
    }
}
