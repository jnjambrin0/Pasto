import PastoFoundation
@testable import PastoSettings
import Testing

/// What the Intelligence pane asks for, and on which Macs it is listed.
struct IntelligenceSettingsTests {
    private let ephemeral = EphemeralDefaults()

    private func model(isModelEnabled: Bool, isScreenAccessMissing: Bool) -> IntelligenceModel {
        IntelligenceModel(
            config: ConfigStore(defaults: ephemeral.defaults),
            suggestions: SuggestionsAvailability(
                isSupported: true,
                isModelEnabled: { isModelEnabled },
                isScreenAccessMissing: { isScreenAccessMissing },
                requestScreenAccess: {}
            )
        )
    }

    @Test func appleIntelligenceOffAsksForItWhateverElseIsMissing() {
        #expect(model(isModelEnabled: false, isScreenAccessMissing: false).requirement == .appleIntelligence)
        #expect(model(isModelEnabled: false, isScreenAccessMissing: true).requirement == .appleIntelligence)
    }

    @Test func withAppleIntelligenceOnlyMissingScreenAccessIsAskedFor() {
        #expect(model(isModelEnabled: true, isScreenAccessMissing: true).requirement == .screenAccess)
        #expect(model(isModelEnabled: true, isScreenAccessMissing: false).requirement == nil)
    }

    @Test func intelligenceIsListedOnlyWhereSuggestionsCanRun() {
        #expect(SettingsPane.listed(hasSuggestions: true) == [.general, .intelligence, .privacy, .shortcuts])
        #expect(SettingsPane.listed(hasSuggestions: false) == [.general, .privacy, .shortcuts])
    }
}
