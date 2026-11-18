import Foundation
import PastoSearch

/// What the search field's own undo remembers: the query and where the cursor was.
nonisolated struct SearchFieldState: Equatable {
    var query = SearchQuery()
    var selection = NSRange(location: 0, length: 0)
}

/// The search field's undo and redo stacks.
///
/// A burst of typing is one step: its first keystroke remembers where the burst started, and
/// that state is pushed when the owner calls `commitPendingTyping()` once the typing pauses.
/// Adding or removing a filter is always a step of its own.
nonisolated struct SearchUndoHistory: Equatable {
    private(set) var current = SearchFieldState()
    private var undoStack: [SearchFieldState] = []
    private var redoStack: [SearchFieldState] = []
    /// The state before the burst of typing in progress.
    private var typingStart: SearchFieldState?

    /// Records that the field went from `current` to `state`.
    ///
    /// - Parameter isTyping: The change is a keystroke that belongs to a burst; otherwise it is
    ///   a step of its own.
    mutating func register(_ state: SearchFieldState, isTyping: Bool) {
        if isTyping {
            if typingStart == nil {
                typingStart = current
            }
        } else {
            commitPendingTyping()
            undoStack.append(current)
        }
        current = state
        redoStack.removeAll()
    }

    /// Ends the burst of typing, making it one undo step.
    mutating func commitPendingTyping() {
        guard let start = typingStart else { return }
        typingStart = nil
        undoStack.append(start)
    }

    /// Goes back one step. Nil when there is nothing to undo.
    mutating func undo() -> SearchFieldState? {
        commitPendingTyping()
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        current = previous
        return previous
    }

    /// Reapplies the step undone last. Nil when there is nothing to redo.
    mutating func redo() -> SearchFieldState? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        current = next
        return next
    }

    /// Forgets every step; the current state stays.
    mutating func removeAll() {
        undoStack.removeAll()
        redoStack.removeAll()
        typingStart = nil
    }
}
