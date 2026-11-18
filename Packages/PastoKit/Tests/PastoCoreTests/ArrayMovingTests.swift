import Foundation
@testable import PastoCore
import Testing

struct ArrayMovingTests {
    private let letters = ["a", "b", "c", "d", "e"]

    @Test func movesForwards() {
        #expect(letters.moving(fromOffsets: [0], toOffset: 3) == ["b", "c", "a", "d", "e"])
    }

    @Test func movesBackwards() {
        #expect(letters.moving(fromOffsets: [3], toOffset: 1) == ["a", "d", "b", "c", "e"])
    }

    @Test func severalElementsEndUpTogetherInTheirOrder() {
        #expect(letters.moving(fromOffsets: [0, 4], toOffset: 2) == ["b", "a", "e", "c", "d"])
        #expect(letters.moving(fromOffsets: [1, 3], toOffset: 5) == ["a", "c", "e", "b", "d"])
    }

    @Test func droppingAnElementNextToItselfChangesNothing() {
        #expect(letters.moving(fromOffsets: [2], toOffset: 2) == letters)
        #expect(letters.moving(fromOffsets: [2], toOffset: 3) == letters)
    }

    @Test func aDestinationOutOfRangeIsTheNearestEnd() {
        #expect(letters.moving(fromOffsets: [2], toOffset: 99) == ["a", "b", "d", "e", "c"])
        #expect(letters.moving(fromOffsets: [2], toOffset: -1) == ["c", "a", "b", "d", "e"])
    }
}
