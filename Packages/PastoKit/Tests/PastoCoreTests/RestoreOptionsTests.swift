import Foundation
import PastoCore
import PastoFoundation
import Testing

struct RestoreOptionsTests {
    @Test func theRawValuesAreStable() {
        #expect(RestoreOptions.nonTextAsPlainText.rawValue == 1)
        #expect(RestoreOptions.textAsPlainText.rawValue == 2)
        #expect(RestoreOptions.plainText.rawValue == 3)
    }

    /// The gesture gives 0 or 3, the setting adds bit 1.
    @Test(arguments: [
        (false, false, 0),
        (true, false, 2),
        (false, true, 3),
        (true, true, 3),
    ])
    func theSettingAndTheModifierCombine(alwaysPlainText: Bool, modifier: Bool, expected: Int) {
        let gesture: RestoreOptions = modifier ? .plainText : []

        #expect(gesture.applying(alwaysPlainText: alwaysPlainText).rawValue == expected)
    }

    @Test func theSettingOnlyAddsTheTextBit() {
        // A menu action that asks for bit 0 alone.
        let action = RestoreOptions.nonTextAsPlainText

        #expect(action.applying(alwaysPlainText: false) == .nonTextAsPlainText)
        #expect(action.applying(alwaysPlainText: true) == .plainText)
    }

    @Test func alwaysPlainTextIsOffByDefault() {
        let ephemeral = EphemeralDefaults()
        let config = ConfigStore(defaults: ephemeral.defaults)

        #expect(ConfigKey.isPasteAsPlainTextEnabled.name == "isPasteAsPlainTextEnabled")
        #expect(config.value(for: .isPasteAsPlainTextEnabled) == false)
    }
}
