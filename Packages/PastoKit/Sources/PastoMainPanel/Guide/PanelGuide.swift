import AppKit
import Foundation

/// Which tip of the panel's guide is on screen, and which come next. Pure: the controller tells
/// it what happens and shows what it says.
///
/// The guide is a short tour of the panel the first times it opens — the cards, search,
/// pinboards, suggestions and the "…" menu — plus a one-line explanation the first time
/// suggestions are used. A mark that has been seen never comes back, unless the user asks for
/// the tips again (Help › Show Tips): one that was read, skipped or set aside by using the panel
/// counts as seen. The tour shows one mark at a time and goes on with "Next"; anything the user
/// does in the panel puts the mark away and leaves the rest for the next opening.
nonisolated struct PanelGuide: Equatable, Sendable {
    /// What the guide can show, each seen once.
    enum Mark: String, CaseIterable, Sendable {
        // The tour, in its order.
        case cards
        case search
        case pinboards
        case suggestions
        case more
        /// The first time suggestions are turned on.
        case suggestionsFirstUse

        static let tour: [Mark] = [.cards, .search, .pinboards, .suggestions, .more]

        var isTourStep: Bool { Self.tour.contains(self) }
    }

    /// How long a mark must have been on screen for closing the panel to count as having read it.
    static let minimumReadingTime: TimeInterval = 1.5

    private(set) var seen: Set<Mark>
    /// The mark on screen.
    private(set) var current: Mark?
    private var shownAt: Date?
    /// Something the user did put the tour away until the panel opens again.
    private var isTourSetAside = false

    init(seen: Set<Mark> = []) {
        self.seen = seen
    }

    // MARK: - What happens

    /// The panel has opened. With `available` the tour steps whose element is on screen now,
    /// returns the mark to show, if any.
    mutating func panelDidOpen(available: Set<Mark>, at now: Date) -> Mark? {
        isTourSetAside = false
        guard current == nil else { return current }
        return show(firstUnseenStep(after: nil, available: available), at: now)
    }

    /// "Next" on a tour step: it is seen, and the next unseen one whose element is on screen
    /// comes up. Nil when the tour is over.
    mutating func next(available: Set<Mark>, at now: Date) -> Mark? {
        guard let current else { return nil }
        seen.insert(current)
        self.current = nil
        guard current.isTourStep else { return nil }
        return show(firstUnseenStep(after: current, available: available), at: now)
    }

    /// "Skip": the whole tour counts as seen.
    mutating func skip() {
        if let current { seen.insert(current) }
        seen.formUnion(Mark.tour)
        current = nil
    }

    /// The user did something in the panel. What it shows they know (`learnt`) is seen; the
    /// mark on screen goes away as seen, and the rest of the tour waits for the next opening.
    mutating func userDidSomething(learnt: Set<Mark>) {
        seen.formUnion(learnt)
        if let current {
            seen.insert(current)
            self.current = nil
        }
        isTourSetAside = true
    }

    /// The panel starts closing. The mark on screen counts as seen if it was there long enough
    /// to read; if not, it comes back at the next opening.
    mutating func panelWillClose(at now: Date) {
        if let current, let shownAt, now.timeIntervalSince(shownAt) >= Self.minimumReadingTime {
            seen.insert(current)
        }
        current = nil
        shownAt = nil
    }

    /// Suggestions were turned on: the first time, their explanation, in place of whatever was
    /// on screen.
    mutating func suggestionsDidTurnOn(at now: Date) -> Mark? {
        userDidSomething(learnt: [.suggestions])
        return show(seen.contains(.suggestionsFirstUse) ? nil : .suggestionsFirstUse, at: now)
    }

    /// Help › Show Tips: every mark can be seen again, and the tour starts over.
    mutating func replay() {
        seen = []
        current = nil
        shownAt = nil
        isTourSetAside = false
    }

    /// Whether a tour step should come up now: the panel is open, nothing is on screen and the
    /// tour has not been set aside since the panel opened.
    func canResumeTour(available: Set<Mark>) -> Bool {
        current == nil && !isTourSetAside && firstUnseenStep(after: nil, available: available) != nil
    }

    /// Resumes the tour where it is, if `canResumeTour`.
    mutating func resumeTour(available: Set<Mark>, at now: Date) -> Mark? {
        guard canResumeTour(available: available) else { return nil }
        return show(firstUnseenStep(after: nil, available: available), at: now)
    }

    // MARK: - What it says

    /// "2 of 5": where `mark` is among the tour steps whose element is on screen.
    func step(of mark: Mark, available: Set<Mark>) -> (number: Int, count: Int)? {
        let steps = Mark.tour.filter { available.contains($0) || $0 == mark }
        guard let index = steps.firstIndex(of: mark) else { return nil }
        return (index + 1, steps.count)
    }

    /// Whether `mark` is the last tour step still to be seen: its button says "Done".
    func isLastStep(_ mark: Mark, available: Set<Mark>) -> Bool {
        mark.isTourStep && firstUnseenStep(after: mark, available: available) == nil
    }

    // MARK: - Keys

    /// What a key typed in the panel shows the user knows. Return, Enter, Space and the quick
    /// paste digits are the cards; ⌘F and typing are search; the tab shortcuts and ⇧⌘N are
    /// pinboards.
    static func learnt(
        byKey keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?,
        quickPasteModifiers: NSEvent.ModifierFlags,
        tabShortcuts: [(keyCode: Int, modifiers: NSEvent.ModifierFlags)]
    ) -> Set<Mark> {
        let modifiers = modifiers.intersection([.command, .option, .control, .shift])
        let key = Int(keyCode)
        if tabShortcuts.contains(where: { $0.keyCode == key && $0.modifiers == modifiers }) {
            return [.pinboards]
        }
        switch key {
        case KeyCodes.returnKey, KeyCodes.enter, KeyCodes.space:
            return [.cards]
        case _ where KeyCodes.digits.contains(key) && !quickPasteModifiers.isEmpty && modifiers == quickPasteModifiers:
            return [.cards]
        case KeyCodes.f where modifiers == .command:
            return [.search]
        case KeyCodes.n where modifiers == [.command, .shift]:
            return [.pinboards]
        default:
            break
        }
        // Typing starts a search.
        let isTyping = modifiers.isDisjoint(with: [.command, .control])
            && characters?.unicodeScalars.contains { CharacterSet.alphanumerics.union(.punctuationCharacters).contains($0) } == true
        return isTyping ? [.search] : []
    }

    private enum KeyCodes {
        static let returnKey = 36
        static let enter = 76
        static let space = 49
        static let f = 3
        static let n = 45
        /// 1–9 on the main row.
        static let digits: Set<Int> = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    // MARK: - Helpers

    private mutating func show(_ mark: Mark?, at now: Date) -> Mark? {
        current = mark
        shownAt = mark == nil ? nil : now
        return mark
    }

    /// The first tour step after `mark` (from the start with nil) that has not been seen and
    /// whose element is on screen.
    private func firstUnseenStep(after mark: Mark?, available: Set<Mark>) -> Mark? {
        let start = mark.flatMap { Mark.tour.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        return Mark.tour[start...].first { !seen.contains($0) && available.contains($0) }
    }
}
