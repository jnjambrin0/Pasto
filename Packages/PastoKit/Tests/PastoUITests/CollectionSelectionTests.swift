import Testing
@testable import PastoUI

@Suite struct CollectionSelectionTests {
    @Test func singleSelectionReplaces() {
        var selection = CollectionSelection()
        selection.select(2, mode: .single, cellCount: 10)
        selection.select(5, mode: .single, cellCount: 10)
        #expect(selection.indexes == [5])
        #expect(selection.rangeStart == 5)
        #expect(selection.cursor == 5)
    }

    @Test func outOfBoundsIsIgnored() {
        var selection = CollectionSelection()
        selection.select(10, mode: .single, cellCount: 10)
        selection.select(-1, mode: .single, cellCount: 10)
        #expect(selection.isEmpty)
    }

    @Test func toggleKeepsSelectionOrder() {
        var selection = CollectionSelection()
        selection.select(4, mode: .single, cellCount: 10)
        selection.select(1, mode: .toggle, cellCount: 10)
        selection.select(7, mode: .toggle, cellCount: 10)
        #expect(selection.indexes == [4, 1, 7])
        #expect(selection.cursor == 7)
        #expect(selection.rangeStart == 7)

        selection.select(7, mode: .toggle, cellCount: 10)
        #expect(selection.indexes == [4, 1])
        #expect(selection.rangeStart == 1)
    }

    @Test func theOnlySelectedCellCannotBeToggledOff() {
        var selection = CollectionSelection()
        selection.select(3, mode: .single, cellCount: 10)
        selection.select(3, mode: .toggle, cellCount: 10)
        #expect(selection.indexes == [3])
    }

    @Test func rangeRunsFromTheAnchorTowardsTheCell() {
        var selection = CollectionSelection()
        selection.select(4, mode: .single, cellCount: 10)
        selection.select(7, mode: .range, cellCount: 10)
        #expect(selection.indexes == [4, 5, 6, 7])
        selection.select(2, mode: .range, cellCount: 10)
        #expect(selection.indexes == [4, 3, 2])
        #expect(selection.rangeStart == 4)
        #expect(selection.cursor == 2)
    }

    @Test func rangeNeedsAnAnchor() {
        var selection = CollectionSelection()
        selection.select(3, mode: .range, cellCount: 10)
        #expect(selection.isEmpty)
    }

    @Test func rangeKeepsUnrelatedRuns() {
        var selection = CollectionSelection()
        selection.select(1, mode: .single, cellCount: 10)
        selection.select(6, mode: .toggle, cellCount: 10)
        selection.select(4, mode: .range, cellCount: 10)
        #expect(selection.indexes == [1, 6, 5, 4])
        // Growing the range until it reaches the other run absorbs it.
        selection.select(1, mode: .range, cellCount: 10)
        #expect(selection.indexes == [6, 5, 4, 3, 2, 1])
    }

    @Test func runsFollowTheOrderOfSelection() {
        var selection = CollectionSelection()
        selection.select(2, mode: .single, cellCount: 10)
        selection.select(4, mode: .toggle, cellCount: 10)
        selection.select(3, mode: .toggle, cellCount: 10)
        // 4 and 3 were selected one after the other and are neighbours: one run, which the
        // range from 3 replaces. 2 was selected apart from them and stays.
        selection.select(6, mode: .range, cellCount: 10)
        #expect(selection.indexes == [2, 3, 4, 5, 6])
    }

    @Test func selectAllAnchorsRangesAtTheLastCell() {
        var selection = CollectionSelection()
        selection.selectAll(cellCount: 5)
        #expect(selection.indexes == [0, 1, 2, 3, 4])
        #expect(selection.rangeStart == 4)
        selection.selectAll(cellCount: 0)
        #expect(selection.rangeStart == nil)
    }

    @Test func aContentChangeAnchorsRangesAtTheLastSelectedCell() {
        var selection = CollectionSelection()
        selection.select(1, mode: .single, cellCount: 10)
        selection.select(3, mode: .range, cellCount: 10)
        #expect(selection.rangeStart == 1)

        selection.remap(cellCount: 10) { $0 }
        #expect(selection.indexes == [1, 2, 3])
        #expect(selection.rangeStart == 3)
    }

    @Test func reloadSelectsTheFirstCell() {
        var selection = CollectionSelection()
        selection.reset(cellCount: 4)
        #expect(selection.indexes == [0])
        #expect(selection.rangeStart == 0)
        selection.reset(cellCount: 0)
        #expect(selection.isEmpty)
        #expect(selection.rangeStart == nil)
    }

    @Test func remapFollowsCellsAndFallsBackToTheFirst() {
        var selection = CollectionSelection()
        selection.select(1, mode: .single, cellCount: 5)
        selection.select(3, mode: .toggle, cellCount: 5)

        selection.remap(cellCount: 6) { $0 + 1 }
        #expect(selection.indexes == [2, 4])
        #expect(selection.rangeStart == 4)

        selection.remap(cellCount: 5) { $0 == 4 ? nil : $0 }
        #expect(selection.indexes == [2])
        #expect(selection.rangeStart == 2)

        selection.remap(cellCount: 4) { _ in nil }
        #expect(selection.indexes == [0])
        selection.remap(cellCount: 0) { _ in nil }
        #expect(selection.isEmpty)
    }
}
