@testable import PastoSettings
import Testing

struct IgnoredIdentifiersTests {
    @Test func addingKeepsTheOrderAndSkipsWhatIsAlreadyThere() {
        #expect(IgnoredIdentifiers.adding(["c", "a", "d", "d"], to: ["a", "b"]) == ["a", "b", "c", "d"])
    }

    @Test func removingLeavesTheRestInOrder() {
        #expect(IgnoredIdentifiers.removing(["b", "x"], from: ["a", "b", "c"]) == ["a", "c"])
    }

    @Test func aSwitchAddsOrRemovesOnlyItsOwnEntry() {
        #expect(IgnoredIdentifiers.setting("b", included: false, in: ["a", "b", "c"]) == ["a", "c"])
        #expect(IgnoredIdentifiers.setting("b", included: true, in: ["a", "c"]) == ["a", "c", "b"])
        #expect(IgnoredIdentifiers.setting("a", included: true, in: ["a", "c"]) == ["a", "c"])
    }
}
