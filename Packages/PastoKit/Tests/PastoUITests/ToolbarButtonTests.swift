import AppKit
import Testing
@testable import PastoUI

@Suite struct ToolbarButtonTests {
    // MARK: Size

    @Test func squareSizesIgnoreTheirContent() {
        #expect(ToolbarButton.Size.medium.size(contentWidth: 100) == CGSize(width: 28, height: 28))
        #expect(ToolbarButton.Size.large.size(contentWidth: 100) == CGSize(width: 32, height: 32))
    }

    @Test func regularSizeFollowsItsContentWithAMinimum() {
        #expect(ToolbarButton.Size.regular.size(contentWidth: 0) == CGSize(width: 32, height: 24))
        #expect(ToolbarButton.Size.regular.size(contentWidth: 8) == CGSize(width: 32, height: 24))
        #expect(ToolbarButton.Size.regular.size(contentWidth: 40) == CGSize(width: 64, height: 24))
    }

    @Test func cornerRadiusIsHalfTheHeight() {
        #expect(ToolbarButton.Size.allCases.map(\.cornerRadius) == [12, 14, 16])
    }

    // MARK: Key equivalent

    private let newPinboard = KeyEquivalent("n", modifiers: [.command, .shift])

    @Test func matchesTheCharacterWhateverItsCase() {
        // With Shift held the key reports "N".
        #expect(newPinboard.matches(characters: "N", modifiers: [.command, .shift]))
        #expect(newPinboard.matches(characters: "n", modifiers: [.command, .shift]))
        #expect(KeyEquivalent("N", modifiers: .command).matches(characters: "n", modifiers: .command))
    }

    @Test func requiresExactlyItsModifiers() {
        #expect(!newPinboard.matches(characters: "n", modifiers: .command))
        #expect(!newPinboard.matches(characters: "n", modifiers: [.command, .shift, .option]))
        #expect(!newPinboard.matches(characters: "m", modifiers: [.command, .shift]))
        #expect(!newPinboard.matches(characters: nil, modifiers: [.command, .shift]))
    }

    @Test func ignoresFlagsThatAreNotModifiers() {
        #expect(newPinboard.matches(characters: "N", modifiers: [.command, .shift, .capsLock, .numericPad, .function]))
    }
}
