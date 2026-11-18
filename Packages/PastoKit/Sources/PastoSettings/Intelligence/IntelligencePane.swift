import SwiftUI

/// Settings › Intelligence. The pane is only listed on a Mac that can run suggestions. Under the
/// switch, a pill says what they still need: Apple Intelligence, or screen recording access once
/// suggestions and Apple Intelligence are both on.
struct IntelligencePane: View {
    @Bindable var model: IntelligenceModel

    var body: some View {
        SettingsPaneLayout {
            SettingsSection(title: SettingsStrings.suggestionsSectionTitle) {
                SettingsToggleRow(
                    title: SettingsStrings.intelligentClipboard,
                    subtitle: SettingsStrings.intelligentClipboardInfo,
                    isOn: model.isPicksEnabled.binding
                ) {
                    if let requirement = model.requirement {
                        SettingsWarningPill(title: title(of: requirement)) {
                            model.perform(requirement)
                        }
                    }
                }
            }
        }
    }

    private func title(of requirement: IntelligenceModel.Requirement) -> String {
        switch requirement {
        case .appleIntelligence: SettingsStrings.requiresAppleIntelligence
        case .screenAccess: SettingsStrings.allowScreenAccess
        }
    }
}
