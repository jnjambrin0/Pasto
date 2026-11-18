import AppKit
import Observation
import PastoCore
import PastoFoundation
import PastoPermissions

/// The state behind the welcome's suggestions step: the setting, what suggestions still need
/// before they can work, and the one thing to do next.
@Observable
final class SuggestionsStepModel {
    /// What stands between the user and working suggestions, in the order it has to be done.
    enum Need: Equatable {
        /// Suggestions are turned off: nothing to do.
        case nothing
        /// Apple Intelligence is off in System Settings.
        case appleIntelligence
        /// Screen recording access, not yet granted to this process.
        case screenRecording
        /// macOS's own confirmation of direct screen capture, which a capture check brings up.
        case confirmation
        /// Everything is in place.
        case ready
    }

    let screenRecording: ScreenRecordingAccessModel
    private(set) var isModelEnabled: Bool
    var isEnabled: Bool {
        didSet { config.set(isEnabled, for: .isPicksEnabled) }
    }

    private let config: ConfigStore
    private let suggestions: OnboardingSuggestions
    private let onContinue: () -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?

    init(config: ConfigStore, suggestions: OnboardingSuggestions, origin: ScreenRecordingRequest.Origin, onContinue: @escaping () -> Void) {
        self.config = config
        self.suggestions = suggestions
        self.onContinue = onContinue
        screenRecording = ScreenRecordingAccessModel(config: config, origin: origin)
        isModelEnabled = suggestions.isModelEnabled()
        isEnabled = config.value(for: .isPicksEnabled)
    }

    isolated deinit {
        observation?.cancel()
    }

    var need: Need {
        Self.need(
            isEnabled: isEnabled,
            isModelEnabled: isModelEnabled,
            isScreenRecordingGranted: screenRecording.isGranted,
            isConfirmed: screenRecording.confirmation == .confirmed
        )
    }

    nonisolated static func need(
        isEnabled: Bool,
        isModelEnabled: Bool,
        isScreenRecordingGranted: Bool,
        isConfirmed: Bool
    ) -> Need {
        guard isEnabled else { return .nothing }
        guard isModelEnabled else { return .appleIntelligence }
        guard isScreenRecordingGranted else { return .screenRecording }
        return isConfirmed ? .ready : .confirmation
    }

    /// Follows screen recording access and Apple Intelligence, looked at again whenever Pasto
    /// comes back to the front.
    func startObserving() {
        screenRecording.startObserving()
        guard observation == nil else { return }
        observation = Task { [weak self] in
            let activations = NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification).map { _ in }
            for await _ in activations {
                guard let self else { return }
                let isModelEnabled = suggestions.isModelEnabled()
                if self.isModelEnabled != isModelEnabled { self.isModelEnabled = isModelEnabled }
            }
        }
    }

    func stopObserving() {
        screenRecording.stopObserving()
        observation?.cancel()
        observation = nil
    }

    /// The switch: turning suggestions on asks for screen recording access there and then, if
    /// that is what they still need and the system has never asked.
    func setEnabled(_ isOn: Bool) {
        isEnabled = isOn
        if isOn, need == .screenRecording, !screenRecording.opensSystemSettings {
            screenRecording.requestAccess()
        }
    }

    /// Does what `need` asks for, or goes on when nothing is missing.
    func performPrimaryAction() {
        switch need {
        case .nothing, .ready:
            goOn()
        case .appleIntelligence:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        case .screenRecording:
            screenRecording.requestAccess()
        case .confirmation:
            Task { await screenRecording.confirm() }
        }
    }

    func goOn() {
        stopObserving()
        onContinue()
    }
}
