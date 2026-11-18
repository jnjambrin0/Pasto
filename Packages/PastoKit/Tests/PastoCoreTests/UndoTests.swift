import Foundation
import PastoCore
import PastoFoundation
import Testing

/// Undo and redo of what the user does to items.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UndoTests {
    private let store: StoreFixture
    private let undoable: UndoableWriter

    init() throws {
        store = try StoreFixture()
        undoable = UndoableWriter(writer: store.writer)
    }

    private var history: [ItemID] {
        store.reader.itemCollection(for: .clipboard).snapshot.ids
    }

    private func items(on pinboard: ListID) -> [ItemID] {
        store.reader.itemCollection(for: pinboard).snapshot.ids
    }

    /// Items "a", "b" and "c", with "a" titled and pinned.
    private func recordThreeAndPinTheFirst() async throws -> (ids: [ItemID], pinboard: ListID) {
        let ids = try await store.record(["a", "b", "c"])
        let pinboard = try await store.writer.perform(author: .user) { context in
            let pinboard = try context.createPinboard(name: "Work", color: .blue)
            try context.pin([ids[0]], to: pinboard)
            try context.setTitle("First", of: ids[0])
            return pinboard
        }
        return (ids, pinboard)
    }

    // MARK: - Reversals

    @Test func aDeletedItemComesBackWholeAndCanBeDeletedAgain() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()
        let before = try #require(store.reader.item(ids[0]))
        let content = store.reader.pasteboardItems(for: ids[0])

        let deletion = try await store.writer.performReversibly(author: .user) { try $0.delete([ids[0], ids[1]]) }.reversal
        #expect(history == [ids[2]])

        let restoration = try await store.writer.performReversibly(author: .user) { try $0.apply(deletion) }.reversal
        #expect(history == [ids[2], ids[1], ids[0]])
        #expect(items(on: pinboard) == [ids[0]])
        #expect(store.reader.item(ids[0]) == before)
        #expect(store.reader.pasteboardItems(for: ids[0]) == content)

        try await store.writer.perform(author: .user) { try $0.apply(restoration) }
        #expect(history == [ids[2]])
        #expect(items(on: pinboard).isEmpty)
    }

    @Test func leavingAListIsReversedWithoutTouchingTheOther() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()

        let fromHistory = try await store.writer.performReversibly(author: .user) { try $0.remove([ids[0]], from: .clipboard) }.reversal
        #expect(history == [ids[2], ids[1]])
        try await store.writer.perform(author: .user) { try $0.apply(fromHistory) }
        #expect(history == [ids[2], ids[1], ids[0]])

        let fromPinboard = try await store.writer.performReversibly(author: .user) { try $0.remove([ids[0]], from: pinboard) }.reversal
        #expect(items(on: pinboard).isEmpty)
        try await store.writer.perform(author: .user) { try $0.apply(fromPinboard) }
        #expect(items(on: pinboard) == [ids[0]])
        #expect(history == [ids[2], ids[1], ids[0]])
    }

    @Test func pinningIsReversedIncludingThePositionsItShifted() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()

        let pin = try await store.writer.performReversibly(author: .user) { try $0.pin([ids[1], ids[2]], to: pinboard) }.reversal
        #expect(items(on: pinboard) == [ids[2], ids[1], ids[0]])

        try await store.writer.perform(author: .user) { try $0.apply(pin) }
        #expect(items(on: pinboard) == [ids[0]])
        #expect(store.reader.item(ids[0])?.displayOrderInPinboard == 0)
        #expect(store.reader.item(ids[1])?.listID == nil)
    }

    @Test func aTransactionThatChangesNoItemHasNothingToReverse() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()

        let nothing = try await store.writer.performReversibly(author: .user) { context in
            try context.pin([ids[0]], to: pinboard)
            try context.renameList(pinboard, to: "Office")
        }.reversal

        #expect(nothing.isEmpty)
    }

    @Test func anItemWhosePinboardIsGoneIsNotBroughtBackOntoIt() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()
        let unpin = try await store.writer.performReversibly(author: .user) { try $0.unpin([ids[0]]) }.reversal
        try await store.writer.perform(author: .user) { try $0.deleteList(pinboard) }

        try await store.writer.perform(author: .user) { try $0.apply(unpin) }

        #expect(store.reader.item(ids[0])?.listID == nil)
        #expect(history == [ids[2], ids[1], ids[0]])
    }

    @Test func aReversalPutsBackOnlyWhatItsTransactionChanged() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()
        let rename = try await store.writer.performReversibly(author: .user) { try $0.setTitle("Renamed", of: ids[0]) }.reversal
        // Changes nobody can undo happen in between.
        try await store.writer.perform(author: .user) { try $0.touch(ids[0], at: .second(9)) }

        try await store.writer.perform(author: .user) { try $0.apply(rename) }

        let item = try #require(store.reader.item(ids[0]))
        #expect(item.title == "First")
        #expect(item.timestamp == .second(9))
        #expect(item.listID == pinboard)
    }

    @Test func aReversalDoesNotTakeAnItemOffThePinboardItIsOnNow() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()
        let unpin = try await store.writer.performReversibly(author: .user) { try $0.unpin([ids[0]]) }.reversal
        let other = try await store.writer.perform(author: .user) { context in
            let other = try context.createPinboard(name: "Home", color: .green)
            try context.pin([ids[0]], to: other)
            try context.deleteList(pinboard)
            return other
        }

        try await store.writer.perform(author: .user) { try $0.apply(unpin) }

        #expect(items(on: other) == [ids[0]])
    }

    // MARK: - The undo manager

    @Test func undoAndRedoGoThroughTheUndoManager() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()
        let collection = store.reader.itemCollection(for: .clipboard)

        try await undoable.perform { try $0.remove([ids[0], ids[1]], from: .clipboard) }
        try await undoable.perform { try $0.setTitle("Third", of: ids[2]) }
        #expect(undoable.undoManager.canUndo)
        #expect(!undoable.undoManager.canRedo)

        // The latest change first.
        let renameUndone = try await collection.change { undoable.undoManager.undo() }
        #expect(renameUndone.snapshot.updatedIDs == [ids[2]])
        #expect(store.reader.item(ids[2])?.title == nil)

        let removalUndone = try await collection.change { undoable.undoManager.undo() }
        #expect(removalUndone.snapshot.ids == [ids[2], ids[1], ids[0]])
        #expect(items(on: pinboard) == [ids[0]])
        #expect(!undoable.undoManager.canUndo)

        let removalRedone = try await collection.change { undoable.undoManager.redo() }
        #expect(removalRedone.snapshot.ids == [ids[2]])
        #expect(undoable.undoManager.canUndo)
        #expect(undoable.undoManager.canRedo)
    }

    /// A change is a step of its own as soon as it is registered, not at the end of the turn of
    /// the run loop, so a change that comes back in the same turn cannot join it. Undoing and
    /// redoing still work, with the redo in the group the undo opens.
    @Test func everyChangeIsAClosedStepAtOnce() async throws {
        let (ids, _) = try await recordThreeAndPinTheFirst()
        let collection = store.reader.itemCollection(for: .clipboard)

        try await undoable.perform { try $0.setTitle("One", of: ids[1]) }
        #expect(undoable.undoManager.groupingLevel == 0)
        try await undoable.perform { try $0.setTitle("Two", of: ids[2]) }
        #expect(undoable.undoManager.groupingLevel == 0)

        _ = try await collection.change { undoable.undoManager.undo() }
        #expect(store.reader.item(ids[2])?.title == nil)
        #expect(store.reader.item(ids[1])?.title == "One")
        #expect(undoable.undoManager.groupingLevel == 0)

        _ = try await collection.change { undoable.undoManager.redo() }
        #expect(store.reader.item(ids[2])?.title == "Two")
        #expect(undoable.undoManager.canUndo)
    }

    @Test func aChangeThatDidNothingIsNotAStepOfUndo() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()

        try await undoable.perform { try $0.pin([ids[0]], to: pinboard) }

        #expect(!undoable.undoManager.canUndo)
    }

    @Test func aChangeThatCannotBeUndoneMakesEarlierChangesPermanent() async throws {
        let (ids, pinboard) = try await recordThreeAndPinTheFirst()
        try await undoable.perform { try $0.setTitle("Renamed", of: ids[0]) }
        #expect(undoable.undoManager.canUndo)

        try await undoable.performIrreversibly { _ = try $0.eraseHistory() }

        // Undoing the rename now would also put the item back in the history it was erased from.
        #expect(!undoable.undoManager.canUndo)
        #expect(history.isEmpty)
        #expect(items(on: pinboard) == [ids[0]])
        #expect(store.reader.item(ids[0])?.title == "Renamed")
    }

    @Test func clearingTheStackMakesEarlierChangesPermanent() async throws {
        let (ids, _) = try await recordThreeAndPinTheFirst()
        try await undoable.perform { try $0.delete([ids[1]]) }

        undoable.removeAllActions()

        #expect(!undoable.undoManager.canUndo)
        #expect(!undoable.undoManager.canRedo)
        #expect(history == [ids[2], ids[0]])
    }
}
