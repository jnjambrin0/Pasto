import Foundation
import os
import PastoFoundation

/// Writes the user's changes to items so that they can be undone.
///
/// The store is written by a single background writer, so there is no context whose undo
/// manager could do this. Instead every change made through here comes back with its reversal,
/// and the reversal goes on an ordinary `UndoManager`: undoing applies it — reversibly, which
/// gives the redo — and so on. The undo manager is the one the panel's window hands out, which
/// is how ⌘Z and ⇧⌘Z get here.
///
/// Only what goes through `perform` can be undone. What the user does to items that cannot be
/// undone — erasing the history, deleting a pinboard — goes through `performIrreversibly`.
/// Captures, restores, maintenance and sync write through the `StoreWriter` directly;
/// `removeAllActions()` is to be called on every restore and every accepted capture, and on any
/// other change by the user that takes items out of the history, after which nothing done
/// before can be undone.
@MainActor
public final class UndoableWriter {
    /// A reversal that may still be on its way: the redo of an undo is registered when the undo
    /// starts and known when it ends. `nil` when there turned out to be nothing to reverse.
    private typealias PendingReversal = Task<ItemChangeReversal?, Never>

    public let undoManager = UndoManager()

    private let writer: StoreWriter
    private let log = Log.logger(.store)
    /// The latest change, undo or redo; the next one waits for it, so that they reach the store
    /// in the order the user made them.
    private var lastOperation: Task<Void, Never>?
    /// Incremented by `removeAllActions()`: a change that was still being written when the
    /// stack was cleared must not put itself on it afterwards.
    private var generation = 0

    public init(writer: StoreWriter) {
        self.writer = writer
        // Changes come back from the writer on continuations of tasks, not one per event: two
        // that end in the same turn of the run loop would make one step if the manager grouped
        // by event. Every change opens and closes a group of its own instead (`register(_:)`):
        // one change, one step of undo.
        //
        // Nothing else registers on this manager without a group: it is the panel's, whose only
        // text views are the search field, which keeps no undo, and the field editor, which
        // AppKit gives an undo manager of its own.
        undoManager.groupsByEvent = false
    }

    /// Runs `change` as one transaction by the user and makes it one step of undo.
    public func perform(_ change: @escaping @Sendable (WritingContext) throws -> Void) async throws {
        let generation = generation
        let previous = lastOperation
        let operation = Task { [writer] in
            await previous?.value
            return try await writer.performReversibly(author: .user, change).reversal
        }
        lastOperation = Task { _ = try? await operation.value }

        let reversal = try await operation.value
        if generation == self.generation, !reversal.isEmpty {
            register(Task { reversal })
        }
    }

    /// Runs `change` as one transaction by the user that cannot be undone, and forgets what
    /// could be undone before it: the reversals on the stack describe the items as they were
    /// before `change`, and putting them back afterwards would bring back what it took away.
    public func performIrreversibly(_ change: @escaping @Sendable (WritingContext) throws -> Void) async throws {
        removeAllActions()
        let previous = lastOperation
        let operation = Task { [writer] in
            await previous?.value
            try await writer.perform(author: .user, change)
        }
        lastOperation = Task { _ = try? await operation.value }
        try await operation.value
    }

    /// Forgets everything that could be undone or redone.
    public func removeAllActions() {
        generation += 1
        undoManager.removeAllActions()
    }

    /// Puts `reversal` on the stack the undo manager is filling: the undo stack normally, the
    /// redo stack while it undoes. A change of the user's is a step of its own; the redo of an
    /// undo goes in the group the manager opens for the undo.
    private func register(_ reversal: PendingReversal) {
        let opensGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if opensGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { target in
            target.register(target.applying(reversal))
        }
        if opensGroup { undoManager.endUndoGrouping() }
    }

    /// Starts applying `pending` and returns the reversal of doing so.
    private func applying(_ pending: PendingReversal) -> PendingReversal {
        let previous = lastOperation
        let operation = Task { [writer, log] () -> ItemChangeReversal? in
            await previous?.value
            guard let reversal = await pending.value else { return nil }
            do {
                let inverse = try await writer.performReversibly(author: .user) { try $0.apply(reversal) }.reversal
                return inverse.isEmpty ? nil : inverse
            } catch {
                log.error("Could not undo or redo a change: \(error)")
                return nil
            }
        }
        lastOperation = Task { _ = await operation.value }
        return operation
    }
}
