@testable import PastoPicks
import Testing

struct PicksGatesTests {
    @Test func offeredNeedsSupportTheSettingAndAppleIntelligence() {
        let all = PicksGates(isSupported: true, isSettingOn: true, isModelEnabled: true, hasScreenAccess: false)
        #expect(all.isOffered)
        #expect(all.isScreenAccessMissing)

        var unsupported = all
        unsupported.isSupported = false
        var settingOff = all
        settingOff.isSettingOn = false
        var modelOff = all
        modelOff.isModelEnabled = false
        for gates in [unsupported, settingOff, modelOff] {
            #expect(!gates.isOffered)
            // Nothing to ask access for while suggestions are not offered.
            #expect(!gates.isScreenAccessMissing)
        }
    }

    @Test func screenAccessIsNotMissingOnceGranted() {
        let gates = PicksGates(isSupported: true, isSettingOn: true, isModelEnabled: true, hasScreenAccess: true)
        #expect(gates.isOffered)
        #expect(!gates.isScreenAccessMissing)
    }

    @Test func availability() {
        #expect(!LanguageModelAvailability.unsupported.isSupported)
        #expect(!LanguageModelAvailability.deviceNotEligible.isSupported)
        #expect(LanguageModelAvailability.appleIntelligenceNotEnabled.isSupported)
        #expect(!LanguageModelAvailability.appleIntelligenceNotEnabled.isEnabled)
        // A model still downloading already counts: the button is offered while it arrives.
        #expect(LanguageModelAvailability.modelNotReady.isEnabled)
        #expect(LanguageModelAvailability.available.isEnabled)
    }

    @Test func theNullClientIsUnsupported() {
        #expect(NullLanguageModelClient().availability == .unsupported)
        #expect(!NullLanguageModelClient().acceptsImages)
    }

    @Test func ignoredApplicationsMatchByContainment() {
        let entries = ["com.1password", ".nordpass", ""]
        #expect(SystemDestination.isIgnored("com.1password.1password", by: entries))
        #expect(SystemDestination.isIgnored("com.nordsec.nordpass", by: entries))
        // An empty entry would match everything: it is ignored itself.
        #expect(!SystemDestination.isIgnored("com.apple.TextEdit", by: entries))
    }
}
