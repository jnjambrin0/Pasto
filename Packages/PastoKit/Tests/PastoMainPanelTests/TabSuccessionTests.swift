import Testing
@testable import PastoMainPanel

@Suite struct TabSuccessionTests {
    private let tabs = ["history", "a", "b", "c"]

    private func successor(of removed: String, remaining: [String]) -> String? {
        TabSuccession.successor(of: removed, in: tabs, remaining: Set(remaining))
    }

    @Test func theNextTabTakesThePlace() {
        #expect(successor(of: "a", remaining: ["history", "b", "c"]) == "b")
    }

    @Test func theLastTabGivesWayToTheOneBefore() {
        #expect(successor(of: "c", remaining: ["history", "a", "b"]) == "b")
    }

    @Test func tabsThatWentTooAreSkipped() {
        #expect(successor(of: "a", remaining: ["history", "c"]) == "c")
        #expect(successor(of: "b", remaining: ["history"]) == "history")
    }

    @Test func nothingIsLeftOrTheTabWasUnknown() {
        #expect(successor(of: "a", remaining: []) == nil)
        #expect(successor(of: "z", remaining: ["history"]) == nil)
    }
}
