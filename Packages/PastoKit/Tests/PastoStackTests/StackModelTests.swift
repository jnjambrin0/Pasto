import AppKit
import Carbon.HIToolbox
import PastoCore
import PastoFoundation
import PastoInput
import Testing
@testable import PastoStack

@Suite struct StackModelTests {
    private let fixture = StackFixture()

    // MARK: - Filling

    @Test func newRowsJoinAtTheTopKeepingTheirOrder() {
        let model = fixture.makeModel()
        model.add(fixture.items("a"))
        model.add(fixture.items("b", "c"))
        #expect(model.texts == ["b", "c", "a"])
    }

    @Test func newRowsJoinAtTheBottomWhenTheDirectionSaysSo() {
        fixture.config.set(.bottom, for: .pasteStackDirection)
        let model = fixture.makeModel()
        model.add(fixture.items("a"))
        model.add(fixture.items("b", "c"))
        #expect(model.texts == ["a", "b", "c"])
    }

    @Test func theSameItemMayFillSeveralRows() {
        let model = fixture.makeModel()
        let item = fixture.item("a")
        model.add([item])
        model.add([item])
        #expect(model.texts == ["a", "a"])
        #expect(model.rows[0].id != model.rows[1].id)
    }

    @Test func aCaptureBecomesARowIfItsItemExists() {
        let model = fixture.makeModel()
        fixture.item("a")
        model.didCapture(ItemID(rawValue: "a"))
        model.didCapture(ItemID(rawValue: "gone"))
        #expect(model.texts == ["a"])
    }

    // MARK: - Pasting

    @Test func pastingTakesTheFirstRowWhateverTheDirection() {
        fixture.config.set(.bottom, for: .pasteStackDirection)
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))

        model.pasteNext()

        #expect(fixture.pastes == [.init(ids: [ItemID(rawValue: "a")], options: [])])
        #expect(model.texts == ["b"])
        #expect(model.undoSteps.count == 1)
        #expect(fixture.closeRequestCount == 0)
    }

    @Test func pastingTheLastRowClosesTheStack() {
        let model = fixture.makeModel()
        model.add(fixture.items("a"))
        model.pasteNext()
        #expect(model.rows.isEmpty)
        #expect(fixture.closeRequestCount == 1)
    }

    @Test func aRowStaysWhenItsPasteFails() {
        let model = fixture.makeModel()
        model.add(fixture.items("a"))
        fixture.pasteSucceeds = false

        model.pasteNext()

        #expect(model.texts == ["a"])
        #expect(model.undoSteps.isEmpty)
        #expect(fixture.closeRequestCount == 0)
    }

    @Test func aGivenRowCanBePastedOutOfTurn() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))
        model.paste(model.rows[1].id)
        #expect(fixture.pastes.map(\.ids) == [[ItemID(rawValue: "b")]])
        #expect(model.texts == ["a", "c"])
    }

    @Test func pasteAllIsOnePasteOfEveryRowAndClosesTheStack() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))

        model.pasteAll()

        #expect(fixture.pastes.map(\.ids) == [["a", "b", "c"].map(ItemID.init(rawValue:))])
        #expect(model.rows.isEmpty)
        #expect(model.undoSteps.isEmpty)
        #expect(fixture.closeRequestCount == 1)
    }

    @Test func aFailedPasteAllLeavesTheStackAsItWas() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))
        fixture.pasteSucceeds = false
        model.pasteAll()
        #expect(model.texts == ["a", "b"])
        #expect(fixture.closeRequestCount == 0)
    }

    // MARK: - Plain text

    @Test func theStackSwitchPastesTextWithoutFormattingAndIsRemembered() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))

        model.togglePlainText()
        model.pasteNext()

        #expect(fixture.pastes.last?.options == .textAsPlainText)
        #expect(fixture.config.value(for: .isPasteStackPlainTextEnabled))
        #expect(fixture.makeModel().isPlainTextToggleOn)
    }

    @Test func theAppWideSettingIsEnoughForPlainText() {
        fixture.config.set(true, for: .isPasteAsPlainTextEnabled)
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))

        model.pasteAll()

        #expect(!model.isPlainTextToggleOn)
        #expect(model.isPlainTextOn)
        #expect(fixture.pastes.last?.options == .textAsPlainText)
    }

    @Test func theLinkPreviewsSettingIsReadWhenTheStackOpens() {
        fixture.config.set(false, for: .isLinkPreviewsEnabled)
        #expect(!fixture.makeModel().isLinkPreviewsOn)
        fixture.config.set(true, for: .isLinkPreviewsEnabled)
        #expect(fixture.makeModel().isLinkPreviewsOn)
    }

    // MARK: - Removing and undoing

    @Test func removingTheLastRowByHandLeavesTheStackOpen() {
        let model = fixture.makeModel()
        model.add(fixture.items("a"))
        model.removeRow(model.rows[0].id)
        #expect(model.rows.isEmpty)
        #expect(fixture.closeRequestCount == 0)
    }

    @Test func removingByItemTakesEveryRowOfItAndClosesAnEmptiedStack() {
        let model = fixture.makeModel()
        let a = fixture.item("a")
        model.add([a, fixture.item("b"), a])

        model.remove(itemIDs: [a.id])
        #expect(model.texts == ["b"])
        #expect(model.undoSteps.count == 2)
        #expect(fixture.closeRequestCount == 0)

        model.remove(itemIDs: [ItemID(rawValue: "b")])
        #expect(fixture.closeRequestCount == 1)
    }

    @Test func undoPutsARowBackUnderTheRowItFollowed() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))
        model.removeRow(model.rows[1].id)
        // The stack changes meanwhile: the row "b" followed is no longer where it was.
        model.add(fixture.items("d"))

        model.undo()

        #expect(model.texts == ["d", "a", "b", "c"])
        #expect(model.undoSteps.isEmpty)
    }

    @Test func undoFallsBackToTheOldIndexAsFarAsTheStackReaches() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))
        model.removeRow(model.rows[2].id)
        // "c" followed "b", which now goes for good.
        fixture.store[ItemID(rawValue: "b")] = nil
        model.reconcileWithStore()

        // Index 2 no longer exists in a stack of one row.
        model.undo()
        #expect(model.texts == ["a", "c"])

        // A first row has no row above it and goes back to the top.
        model.removeRow(model.rows[0].id)
        model.undo()
        #expect(model.texts == ["a", "c"])
    }

    @Test func everyPastedRowCanBeBroughtBack() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))
        model.pasteNext()
        model.undo()
        #expect(model.texts == ["a", "b"])
    }

    // MARK: - Ordering

    @Test func reversingTurnsTheListAndTheDirectionAndForgetsTheUndoSteps() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))
        model.removeRow(model.rows[0].id)

        model.reverseOrder()

        #expect(model.texts == ["c", "b"])
        #expect(model.direction == .bottom)
        #expect(fixture.config.value(for: .pasteStackDirection) == .bottom)
        #expect(model.undoSteps.isEmpty)

        model.add(fixture.items("d"))
        #expect(model.texts == ["c", "b", "d"])
    }

    @Test func movingARowCountsItsIndexAmongTheOthers() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))
        let a = model.rows[0].id

        model.move(a, to: 1)
        #expect(model.texts == ["b", "a", "c"])
        model.move(a, to: 5)
        #expect(model.texts == ["b", "c", "a"])
        model.move(a, to: 0)
        #expect(model.texts == ["a", "b", "c"])
    }

    @Test func droppedRowsGoWhereTheyWereDroppedWhateverTheDirection() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))

        model.insert(fixture.items("c", "d"), at: 1)
        #expect(model.texts == ["a", "c", "d", "b"])
        model.insert(fixture.items("e"), at: 9)
        #expect(model.texts == ["a", "c", "d", "b", "e"])
        #expect(model.undoSteps.isEmpty)
    }

    // MARK: - Dragging

    @Test func aDragThatComesToNothingPutsTheRowBackWhereItStarted() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))
        let a = model.rows[0].id

        model.beginDrag(a)
        model.move(a, to: 2)
        model.endDrag(.cancelled)

        #expect(model.texts == ["a", "b", "c"])
        #expect(model.undoSteps.isEmpty)
    }

    @Test func aRowDroppedOnThePanelStaysWhereTheDragLeftIt() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))
        let a = model.rows[0].id

        model.beginDrag(a)
        model.move(a, to: 2)
        model.endDrag(.droppedInPanel)

        #expect(model.texts == ["b", "c", "a"])
        #expect(model.undoSteps.isEmpty)
    }

    @Test func aRowDroppedOutsideLeavesTheStackAndUndoPutsItBackWhereItStarted() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))
        let b = model.rows[1].id

        model.beginDrag(b)
        model.move(b, to: 0)
        model.endDrag(.droppedOutside)
        #expect(model.texts == ["a", "c"])
        #expect(fixture.closeRequestCount == 0)

        model.undo()
        #expect(model.texts == ["a", "b", "c"])
    }

    @Test func draggingOutTheLastRowClosesTheStack() {
        let model = fixture.makeModel()
        model.add(fixture.items("a"))
        model.beginDrag(model.rows[0].id)
        model.endDrag(.droppedOutside)
        #expect(model.rows.isEmpty)
        #expect(fixture.closeRequestCount == 1)
    }

    @Test func aRowThatLeftDuringItsDragIsLeftAlone() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))
        model.beginDrag(model.rows[0].id)
        model.pasteNext()

        model.endDrag(.cancelled)
        #expect(model.texts == ["b"])
        model.endDrag(.droppedOutside)
        #expect(model.texts == ["b"])
        #expect(model.undoSteps.count == 1)
    }

    // MARK: - Hot keys

    @Test func theHotKeysAreHeldOnlyWhileThereAreRows() {
        let model = fixture.makeModel()
        #expect(fixture.hotKeys.callers.isEmpty)

        model.add(fixture.items("a"))
        #expect(fixture.hotKeys.callers == ["pasteStackPasteShortcut", "pasteStackPasteAllShortcut"])
        #expect(fixture.hotKeys.shortcuts["pasteStackPasteShortcut"]?.keyCode == kVK_ANSI_V)
        #expect(fixture.hotKeys.shortcuts["pasteStackPasteShortcut"]?.modifiers == .command)
        #expect(fixture.hotKeys.shortcuts["pasteStackPasteAllShortcut"]?.modifiers == [.control, .option, .command])

        model.removeRow(model.rows[0].id)
        #expect(fixture.hotKeys.callers.isEmpty)

        model.undo()
        #expect(fixture.hotKeys.callers.count == 2)
    }

    @Test func theHotKeysPaste() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b", "c"))

        fixture.hotKeys.press(.pasteNext)
        #expect(model.texts == ["b", "c"])

        fixture.hotKeys.press(.pasteAll)
        #expect(fixture.pastes.count == 2)
        #expect(model.rows.isEmpty)
    }

    @Test func closingGivesTheHotKeysBackAndForgetsTheUndoSteps() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))
        model.removeRow(model.rows[0].id)

        model.tearDown()

        #expect(fixture.hotKeys.callers.isEmpty)
        #expect(model.undoSteps.isEmpty)
    }

    @Test func aClosedStackTakesNoRowsAndHoldsNoHotKeys() {
        let model = fixture.makeModel()
        model.add(fixture.items("a"))

        model.tearDown()
        model.insert(fixture.items("b"), at: 0)
        model.undo()

        #expect(model.texts == ["a"])
        #expect(fixture.hotKeys.callers.isEmpty)
    }

    // MARK: - Store changes

    @Test func rowsAndUndoStepsOfDeletedItemsGoWithoutClosingTheStack() {
        let model = fixture.makeModel()
        model.add(fixture.items("a", "b"))
        model.removeRow(model.rows[0].id)
        fixture.store.removeAll()

        model.reconcileWithStore()

        #expect(model.rows.isEmpty)
        #expect(model.undoSteps.isEmpty)
        #expect(fixture.hotKeys.callers.isEmpty)
        #expect(fixture.closeRequestCount == 0)
    }

    @Test func rowsTakeTheCurrentValueOfTheirItems() {
        let model = fixture.makeModel()
        model.add(fixture.items("a"))
        let rowID = model.rows[0].id
        fixture.store[ItemID(rawValue: "a")]?.title = "Renamed"

        model.reconcileWithStore()

        #expect(model.rows.map(\.id) == [rowID])
        #expect(model.rows[0].item.title == "Renamed")
    }
}
