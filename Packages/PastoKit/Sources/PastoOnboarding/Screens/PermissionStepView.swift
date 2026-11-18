import PastoPermissions
import PastoUI
import SwiftUI

/// The welcome's step for Accessibility ("paste into other apps") or pasteboard access: the
/// texts of the permission windows, the permission's state as it is now, and the way to grant it
/// or to leave it for later.
///
/// Granted while the step is on show, the state turns green and the step goes on by itself a
/// moment later; already granted when it comes, the step waits for "Continue".
struct PermissionStepView: View {
    let model: AccessRequestModel

    var body: some View {
        OnboardingStep(
            illustration: model.permission == .accessibility ? .accessibility : .pasteboard,
            title: model.permission.title,
            subtitle: model.permission.subtitle,
            footnote: footnote
        ) {
            OnboardingCard {
                StepStatusRow(state: model.isAccessEnabled ? .done : .pending, title: statusTitle, detail: statusDetail, isLast: true)
            }
        } buttons: {
            if model.isAccessEnabled {
                Button(OnboardingStrings.continueAction, action: model.skip)
                    .buttonStyle(PastoButtonStyle(.filled))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(OnboardingStrings.notNow, action: model.skip)
                    .buttonStyle(PastoButtonStyle(.plain))
                    .keyboardShortcut(.cancelAction)
                Button(model.primaryActionTitle, action: model.performPrimaryAction)
                    .buttonStyle(PastoButtonStyle(.filled))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: model.startObserving)
        .onDisappear(perform: model.stopObserving)
    }

    private var statusTitle: String {
        switch model.permission {
        case .accessibility: OnboardingStrings.accessibilitySettingName
        case .pasteboard: OnboardingStrings.pasteboardSettingName
        }
    }

    private var statusDetail: String {
        switch model.permission {
        case .accessibility:
            model.isAccessEnabled ? OnboardingStrings.accessibilityAllowed : OnboardingStrings.accessibilityNotAllowed
        case .pasteboard:
            switch model.pasteboardAccess {
            case .alwaysAllowed: OnboardingStrings.pasteboardAllowed
            case .ask: OnboardingStrings.pasteboardAsks
            case .alwaysDenied: OnboardingStrings.pasteboardDenied
            case .undetermined: OnboardingStrings.pasteboardUndetermined
            }
        }
    }

    /// What to do in System Settings once the step has sent the user there. The pasteboard's
    /// subtitle already says it.
    private var footnote: String? {
        guard model.permission == .accessibility, !model.isAccessEnabled, model.opensSystemSettings else { return nil }
        return OnboardingStrings.accessibilityHint
    }
}
