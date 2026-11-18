@testable import PastoOnboarding
import Testing

/// What the welcome's suggestions step asks for next.
struct SuggestionsStepTests {
    @Test func turnedOffNeedsNothing() {
        #expect(SuggestionsStepModel.need(isEnabled: false, isModelEnabled: false, isScreenRecordingGranted: false, isConfirmed: false) == .nothing)
        #expect(SuggestionsStepModel.need(isEnabled: false, isModelEnabled: true, isScreenRecordingGranted: true, isConfirmed: true) == .nothing)
    }

    @Test func appleIntelligenceComesFirst() {
        #expect(SuggestionsStepModel.need(isEnabled: true, isModelEnabled: false, isScreenRecordingGranted: false, isConfirmed: false) == .appleIntelligence)
        #expect(SuggestionsStepModel.need(isEnabled: true, isModelEnabled: false, isScreenRecordingGranted: true, isConfirmed: true) == .appleIntelligence)
    }

    @Test func thenScreenRecording() {
        #expect(SuggestionsStepModel.need(isEnabled: true, isModelEnabled: true, isScreenRecordingGranted: false, isConfirmed: false) == .screenRecording)
        // A check made in an earlier run does not stand in for the access this process lacks.
        #expect(SuggestionsStepModel.need(isEnabled: true, isModelEnabled: true, isScreenRecordingGranted: false, isConfirmed: true) == .screenRecording)
    }

    @Test func thenMacOSConfirmation() {
        #expect(SuggestionsStepModel.need(isEnabled: true, isModelEnabled: true, isScreenRecordingGranted: true, isConfirmed: false) == .confirmation)
    }

    @Test func readyOnceConfirmed() {
        #expect(SuggestionsStepModel.need(isEnabled: true, isModelEnabled: true, isScreenRecordingGranted: true, isConfirmed: true) == .ready)
    }
}
