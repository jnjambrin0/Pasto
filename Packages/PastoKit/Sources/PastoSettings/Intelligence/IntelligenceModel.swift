import AppKit
import Observation
import PastoCore
import PastoFoundation

/// The state behind the Intelligence pane.
@Observable
final class IntelligenceModel {
    let isPicksEnabled: Setting<Bool>
    private let suggestions: SuggestionsAvailability

    /// System Settings › Apple Intelligence & Siri, where Apple Intelligence is turned on.
    private static let appleIntelligenceSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")

    init(config: ConfigStore, suggestions: SuggestionsAvailability) {
        isPicksEnabled = Setting(.isPicksEnabled, in: config)
        self.suggestions = suggestions
    }

    /// What the suggestions row asks for under its switch, if anything. Apple Intelligence comes
    /// first, whether suggestions are on or not; screen access only matters once both are on.
    var requirement: Requirement? {
        if !suggestions.isModelEnabled() {
            .appleIntelligence
        } else if suggestions.isScreenAccessMissing() {
            .screenAccess
        } else {
            nil
        }
    }

    enum Requirement {
        case appleIntelligence
        case screenAccess
    }

    func perform(_ requirement: Requirement) {
        switch requirement {
        case .appleIntelligence:
            // Pasto has no help pages of its own, so this opens the place where Apple
            // Intelligence is turned on.
            if let url = Self.appleIntelligenceSettingsURL {
                NSWorkspace.shared.open(url)
            }
        case .screenAccess:
            suggestions.requestScreenAccess()
        }
    }
}
