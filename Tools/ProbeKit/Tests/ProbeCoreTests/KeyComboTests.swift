import CoreGraphics
import Testing
@testable import ProbeCore

@Suite struct KeyComboTests {
    @Test func parsesModifiersAndCharacterKeys() throws {
        #expect(try KeyCombo(parsing: "cmd+shift+v") == KeyCombo(modifiers: [.command, .shift], key: .character("v")))
        #expect(try KeyCombo(parsing: "cmd+1") == KeyCombo(modifiers: .command, key: .character("1")))
        #expect(try KeyCombo(parsing: "cmd+f") == KeyCombo(modifiers: .command, key: .character("f")))
        #expect(try KeyCombo(parsing: "Ctrl+Alt+X") == KeyCombo(modifiers: [.control, .option], key: .character("x")))
    }

    @Test func parsesNamedKeys() throws {
        #expect(try KeyCombo(parsing: "return") == KeyCombo(modifiers: [], key: .named(.return)))
        #expect(try KeyCombo(parsing: "shift+return") == KeyCombo(modifiers: .shift, key: .named(.return)))
        #expect(try KeyCombo(parsing: "escape").key == .named(.escape))
        #expect(try KeyCombo(parsing: "esc").key == .named(.escape))
        #expect(try KeyCombo(parsing: "delete").key == .named(.delete))
        #expect(try KeyCombo(parsing: "backspace").key == .named(.delete))
        for name in ["left", "right", "space", "tab"] {
            #expect(try KeyCombo(parsing: name).key == .named(try #require(NamedKey(rawValue: name))))
        }
    }

    @Test func aTrailingPlusIsThePlusKey() throws {
        #expect(try KeyCombo(parsing: "cmd++") == KeyCombo(modifiers: .command, key: .character("+")))
        #expect(try KeyCombo(parsing: "+") == KeyCombo(modifiers: [], key: .character("+")))
    }

    @Test(arguments: ["", "cmd+", "cmd+shift", "hyper+v", "cmd++v", "cmd+notakey"])
    func rejectsMalformedCombos(_ text: String) {
        #expect(throws: ProbeError.self) { try KeyCombo(parsing: text) }
    }

    @Test func namedKeysUseFixedVirtualKeyCodes() {
        let expected: [NamedKey: UInt16] = [
            .return: 36, .tab: 48, .space: 49, .delete: 51, .escape: 53,
            .left: 123, .right: 124, .down: 125, .up: 126,
        ]
        for (key, code) in expected { #expect(key.keyCode == code) }
        #expect(Set(NamedKey.allCases.map(\.keyCode)).count == NamedKey.allCases.count)
    }

    @Test func eventFlagsCombineModifiersWithWhatTheKeyImplies() throws {
        #expect(try KeyCombo(parsing: "cmd+shift+v").eventFlags == [.maskCommand, .maskShift])
        #expect(try KeyCombo(parsing: "return").eventFlags == [])
        #expect(try KeyCombo(parsing: "shift+left").eventFlags == [.maskShift, .maskSecondaryFn, .maskNumericPad])
    }
}
