import PastoFoundation
import PastoInput
@testable import PastoSettings
import Testing

/// The modifier keys offered for quick paste and plain text mode.
struct ModifierChoiceTests {
    @Test func theOptionsStoreTheCocoaModifierBits() {
        #expect(ModifierChoice.quickPasteOptions.map(\.storedFlags) == [0x100000, 0x40000, 0x80000])
        #expect(ModifierChoice.plainTextOptions.map(\.storedFlags) == [0x100000, 0x20000, 0x40000, 0x80000])
    }

    @Test func aStoredValueSelectsItsOption() {
        let selection = ModifierChoice.selection(forStoredFlags: 0x80000, among: ModifierChoice.quickPasteOptions, default: 0x100000)

        #expect(selection == .option)
    }

    @Test(arguments: [0, 0x20000, 0x180000])
    func aValueThatIsNotOfferedReadsAsTheDefault(storedFlags: Int) {
        let selection = ModifierChoice.selection(forStoredFlags: storedFlags, among: ModifierChoice.quickPasteOptions, default: 0x100000)

        #expect(selection == .command)
    }

    @Test func theDefaultsOfTheSettingsAreAmongTheirOptions() {
        #expect(ModifierChoice.quickPasteOptions.contains { $0.storedFlags == ConfigKey.quickPasteModifierFlags.defaultValue })
        #expect(ModifierChoice.plainTextOptions.contains { $0.storedFlags == ConfigKey.plainTextModifierFlags.defaultValue })
    }
}
