import Foundation
import PastoSearch
import Testing
@testable import PastoMainPanel

private let mail = SearchFilter(type: .app, value: "Mail")
private let link = SearchFilter(type: .type, value: "Link")

/// The field's content for a query, with a bare attachment character for every filter.
private func fieldText(_ query: SearchQuery) -> NSAttributedString {
    SearchFieldText.attributedString(for: query, textAttributes: [:]) { _ in
        NSAttributedString(string: String(SearchFieldText.attachmentCharacter))
    }
}

private func fieldText(_ components: SearchQuery.Component...) -> NSAttributedString {
    fieldText(SearchQuery(components: components))
}

private func cursor(_ location: Int) -> NSRange {
    NSRange(location: location, length: 0)
}

@Suite struct SearchFieldTextTests {
    @Test func readsWordsAndSpacesAsSeparateTokens() {
        let text = NSAttributedString(string: "meeting  slides ")
        #expect(SearchFieldText.query(in: text).components == [
            .token("meeting"), .token("  "), .token("slides"), .token(" "),
        ])
    }

    @Test func readsBackWhatItDraws() {
        let query = SearchQuery(components: [.filter(mail), .filter(link), .token("meeting"), .token(" "), .token("slides")])
        let text = fieldText(query)
        #expect(text.string == "\u{FFFC}\u{FFFC}meeting slides")
        #expect(SearchFieldText.query(in: text) == query)
    }

    @Test func anAttachmentCharacterWithoutAFilterReadsAsASpace() {
        let text = NSAttributedString(string: "a\u{FFFC}b")
        #expect(SearchFieldText.query(in: text).components == [.token("a"), .token(" "), .token("b")])
    }

    /// Text typed right after a token inherits its attributes; it is still text.
    @Test func textInsideAFilterRunIsText() {
        let text = NSMutableAttributedString(attributedString: fieldText(.filter(mail)))
        text.replaceCharacters(in: cursor(1), with: "x")
        #expect(text.attribute(.searchFilter, at: 1, effectiveRange: nil) != nil)
        #expect(SearchFieldText.query(in: text).components == [.filter(mail), .token("x")])
    }

    @Test func aFilterIsOneCharacterLong() {
        let query = SearchQuery(components: [.filter(mail), .token("añ"), .token(" ")])
        #expect(SearchFieldText.length(of: query) == 4)
        #expect(fieldText(query).length == 4)
    }

    @Test func pastedLineFeedsAndCarriageReturnsBecomeOneSpaceEach() {
        #expect(SearchFieldText.singleLine("a\nb\rc\r\nd") == "a b c  d")
        #expect(SearchFieldText.singleLine("a\u{2028}b") == "a\u{2028}b")
        #expect(SearchFieldText.singleLine("plain") == "plain")
    }
}

@Suite struct SearchInputCoordinatorTests {
    private final class Recorder {
        var queries: [SearchQuery] = []
        var views: [(text: String, selection: NSRange)] = []
        var candidates: [SearchInputCoordinator.Candidate?] = []
    }

    private func makeCoordinator() -> (SearchInputCoordinator, Recorder) {
        let recorder = Recorder()
        // The pause that ends a burst of typing never comes: bursts are covered by the history's tests.
        let coordinator = SearchInputCoordinator(render: fieldText) { _ in throw CancellationError() }
        coordinator.onUpdateQuery = { recorder.queries.append($0) }
        coordinator.onUpdateView = { recorder.views.append(($0.string, $1)) }
        coordinator.onUpdateSuggestion = { recorder.candidates.append($0) }
        return (coordinator, recorder)
    }

    @Test func acceptsAnEditThatLeavesTheQueryInOrder() {
        let (coordinator, recorder) = makeCoordinator()
        #expect(coordinator.textShouldChange(to: NSAttributedString(string: "me"), selection: cursor(2)))
        #expect(coordinator.query.components == [.token("me")])
        #expect(recorder.queries == [coordinator.query])
        #expect(recorder.views.isEmpty)
    }

    @Test func acceptsAnEditThatDoesNotChangeTheQueryWithoutReportingIt() {
        let (coordinator, recorder) = makeCoordinator()
        _ = coordinator.textShouldChange(to: NSAttributedString(string: "me"), selection: cursor(2))
        #expect(coordinator.textShouldChange(to: NSAttributedString(string: "me"), selection: cursor(1)))
        #expect(recorder.queries.count == 1)
    }

    /// Text typed before a token moves behind it: the field is redrawn with the cursor at the
    /// end, and the edit as typed is refused.
    @Test func redrawsTheFieldWhenAnEditLeavesTextBeforeAFilter() {
        let (coordinator, recorder) = makeCoordinator()
        coordinator.setQuery(SearchQuery(components: [.filter(mail)]), updatesSuggestion: false)
        recorder.views.removeAll()

        let proposed = fieldText(.token("x"), .filter(mail))
        #expect(!coordinator.textShouldChange(to: proposed, selection: cursor(1)))
        #expect(coordinator.query.components == [.filter(mail), .token("x")])
        #expect(recorder.views.count == 1)
        #expect(recorder.views[0].text == "\u{FFFC}x")
        #expect(recorder.views[0].selection == cursor(2))
        #expect(recorder.candidates.last == .some(nil))
    }

    @Test func aQuerySetFromOutsideIsPutInOrder() {
        let (coordinator, recorder) = makeCoordinator()
        coordinator.setQuery(
            SearchQuery(components: [.token("x"), .filter(mail), .filter(link), .filter(mail)]),
            updatesSuggestion: false
        )
        #expect(coordinator.query.components == [.filter(mail), .filter(link), .token("x")])
        #expect(recorder.views.last?.text == "\u{FFFC}\u{FFFC}x")
        #expect(recorder.candidates.last == .some(nil))
    }

    @Test func settingTheQueryFromOutsideDrawsItWithTheCursorAtTheEnd() {
        let (coordinator, recorder) = makeCoordinator()
        coordinator.setQuery(SearchQuery(text: "meeting"), updatesSuggestion: true)
        #expect(recorder.views.map(\.text) == ["meeting"])
        #expect(recorder.views[0].selection == cursor(7))
        #expect(recorder.queries == [SearchQuery(text: "meeting")])
        #expect(recorder.candidates.last??.index == 0)

        // The same query again changes nothing.
        coordinator.setQuery(SearchQuery(text: "meeting"), updatesSuggestion: true)
        #expect(recorder.queries.count == 1)
    }

    @Test func theCandidateIsTheComponentTheCursorIsOnOrRightAfter() {
        let (coordinator, _) = makeCoordinator()
        // "￼ab cd": the filter is at 0, "ab" at 1–3, " " at 3–4, "cd" at 4–6.
        coordinator.setQuery(
            SearchQuery(components: [.filter(mail), .token("ab"), .token(" "), .token("cd")]),
            updatesSuggestion: false
        )
        #expect(coordinator.candidate(at: 0)?.index == 0)
        #expect(coordinator.candidate(at: 1)?.index == 0)
        #expect(coordinator.candidate(at: 2)?.index == 1)
        #expect(coordinator.candidate(at: 3)?.index == 1)
        #expect(coordinator.candidate(at: 3)?.range == NSRange(location: 1, length: 2))
        #expect(coordinator.candidate(at: 4)?.index == 2)
        #expect(coordinator.candidate(at: 6)?.component == .token("cd"))
        #expect(coordinator.candidate(at: 7) == nil)
    }

    @Test func anEmptyFieldHasNoCandidate() {
        let (coordinator, recorder) = makeCoordinator()
        coordinator.selectionDidChange(cursor(0))
        #expect(recorder.candidates == [nil])
    }

    @Test func undoAndRedoRestoreTheQueryAndTheCursor() {
        let (coordinator, recorder) = makeCoordinator()
        _ = coordinator.textShouldChange(to: NSAttributedString(string: "me"), selection: cursor(2))
        coordinator.setQuery(SearchQuery(components: [.filter(mail)]), updatesSuggestion: false)

        #expect(coordinator.undo())
        #expect(coordinator.query.components == [.token("me")])
        #expect(recorder.views.last?.text == "me")
        #expect(recorder.views.last?.selection == cursor(2))
        #expect(recorder.candidates.last == .some(nil))

        #expect(coordinator.undo())
        #expect(coordinator.query.isEmpty)
        #expect(!coordinator.undo())

        #expect(coordinator.redo())
        #expect(coordinator.redo())
        #expect(coordinator.query.components == [.filter(mail)])
        #expect(!coordinator.redo())
    }

    @Test func clearingCanKeepOrForgetTheUndoHistory() {
        let (coordinator, _) = makeCoordinator()
        coordinator.setQuery(SearchQuery(text: "meeting"), updatesSuggestion: false)
        coordinator.clear(keepingUndoHistory: true)
        #expect(coordinator.query.isEmpty)
        #expect(coordinator.undo())
        #expect(coordinator.query == SearchQuery(text: "meeting"))

        coordinator.clear(keepingUndoHistory: false)
        #expect(!coordinator.undo())
    }
}

@Suite struct SearchUndoHistoryTests {
    private func state(_ text: String) -> SearchFieldState {
        SearchFieldState(query: SearchQuery(text: text), selection: cursor(text.utf16.count))
    }

    @Test func aBurstOfTypingIsUndoneAtOnce() {
        var history = SearchUndoHistory()
        for text in ["m", "me", "mee"] {
            history.register(state(text), isTyping: true)
        }
        #expect(history.undo() == SearchFieldState())
        #expect(history.undo() == nil)
        #expect(history.redo() == state("mee"))
    }

    @Test func aPauseSplitsTheTypingIntoSteps() {
        var history = SearchUndoHistory()
        history.register(state("m"), isTyping: true)
        history.register(state("me"), isTyping: true)
        history.commitPendingTyping()
        history.register(state("mee"), isTyping: true)
        history.register(state("meet"), isTyping: true)

        #expect(history.undo() == state("me"))
        #expect(history.undo() == SearchFieldState())
    }

    @Test func aPauseWithNothingTypedSinceAddsNoStep() {
        var history = SearchUndoHistory()
        history.register(state("m"), isTyping: true)
        history.commitPendingTyping()
        history.commitPendingTyping()
        #expect(history.undo() == SearchFieldState())
        #expect(history.undo() == nil)
    }

    /// Adding a filter ends the burst before it and is a step of its own.
    @Test func anImmediateChangeIsItsOwnStep() {
        var history = SearchUndoHistory()
        history.register(state("m"), isTyping: true)
        history.register(state("me"), isTyping: true)
        let withFilter = SearchFieldState(query: SearchQuery(components: [.filter(mail)]), selection: cursor(1))
        history.register(withFilter, isTyping: false)

        #expect(history.current == withFilter)
        #expect(history.undo() == state("me"))
        #expect(history.undo() == SearchFieldState())
        #expect(history.undo() == nil)
    }

    @Test func aNewChangeForgetsWhatCouldBeRedone() {
        var history = SearchUndoHistory()
        history.register(state("a"), isTyping: false)
        history.register(state("b"), isTyping: false)
        #expect(history.undo() == state("a"))
        history.register(state("c"), isTyping: true)
        #expect(history.redo() == nil)
        #expect(history.undo() == state("a"))
    }

    @Test func removingAllKeepsTheCurrentState() {
        var history = SearchUndoHistory()
        history.register(state("a"), isTyping: false)
        history.register(state("b"), isTyping: true)
        history.removeAll()
        #expect(history.current == state("b"))
        #expect(history.undo() == nil)
        #expect(history.redo() == nil)
    }
}
