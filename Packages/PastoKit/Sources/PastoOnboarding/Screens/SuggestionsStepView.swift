import PastoPermissions
import PastoUI
import SwiftUI

/// The welcome's suggestions step: what suggestions are and that they happen on the Mac, the
/// switch that turns them on, and, while they are on, what they still need — Apple Intelligence,
/// screen recording access, and macOS's confirmation of direct capture, brought up here by a
/// capture check rather than in the middle of using Pasto.
struct SuggestionsStepView: View {
    @Bindable var model: SuggestionsStepModel

    var body: some View {
        OnboardingStep(
            illustration: .suggestions,
            title: OnboardingStrings.suggestionsTitle,
            subtitle: OnboardingStrings.suggestionsSubtitle,
            footnote: footnote
        ) {
            OnboardingCard {
                OnboardingRow(
                    title: OnboardingStrings.suggestionsSwitchTitle,
                    subtitle: OnboardingStrings.suggestionsSwitchSubtitle,
                    isLast: !model.isEnabled
                ) {
                    Toggle(OnboardingStrings.suggestionsSwitchTitle, isOn: Binding(get: { model.isEnabled }, set: model.setEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                if model.isEnabled {
                    statusRows
                }
            }
        } buttons: {
            switch model.need {
            case .nothing, .ready:
                Button(OnboardingStrings.continueAction, action: model.goOn)
                    .buttonStyle(PastoButtonStyle(.filled))
                    .keyboardShortcut(.defaultAction)
            case .appleIntelligence, .screenRecording, .confirmation:
                Button(OnboardingStrings.notNow, action: model.goOn)
                    .buttonStyle(PastoButtonStyle(.plain))
                    .keyboardShortcut(.cancelAction)
                Button(primaryActionTitle, action: model.performPrimaryAction)
                    .buttonStyle(PastoButtonStyle(.filled))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.screenRecording.confirmation == .running)
            }
        }
        .onAppear(perform: model.startObserving)
        .onDisappear(perform: model.stopObserving)
    }

    @ViewBuilder private var statusRows: some View {
        if !model.isModelEnabled {
            StepStatusRow(
                state: .problem,
                title: OnboardingStrings.appleIntelligenceTitle,
                detail: OnboardingStrings.appleIntelligenceOff,
                isLast: true
            )
        } else {
            let access = model.screenRecording
            StepStatusRow(
                state: access.isGranted ? .done : .pending,
                title: OnboardingStrings.screenRecordingSettingName,
                detail: access.isGranted
                    ? OnboardingStrings.screenRecordingAllowed
                    : access.opensSystemSettings ? OnboardingStrings.screenRecordingWaiting : OnboardingStrings.screenRecordingNotAllowed,
                isLast: !access.isGranted
            )
            if access.isGranted {
                StepStatusRow(
                    state: confirmationState,
                    title: OnboardingStrings.confirmationTitle,
                    detail: confirmationDetail,
                    isLast: true
                )
            }
        }
    }

    private var confirmationState: StepStatusRow.State {
        switch model.screenRecording.confirmation {
        case .pending: .pending
        case .running: .working
        case .confirmed: .done
        case .failed: .problem
        }
    }

    private var confirmationDetail: String {
        switch model.screenRecording.confirmation {
        case .pending, .running: OnboardingStrings.confirmationPending
        case .confirmed: OnboardingStrings.confirmationDone
        case .failed: OnboardingStrings.confirmationFailed
        }
    }

    private var primaryActionTitle: String {
        switch model.need {
        case .appleIntelligence: OnboardingStrings.openSystemSettings
        case .screenRecording:
            model.screenRecording.opensSystemSettings ? OnboardingStrings.openSystemSettings : OnboardingStrings.allowScreenRecording
        case .confirmation: model.screenRecording.confirmation == .running ? OnboardingStrings.checking : OnboardingStrings.runCheck
        case .nothing, .ready: OnboardingStrings.continueAction
        }
    }

    /// What happens next, when the user is in the middle of it.
    private var footnote: String? {
        switch model.need {
        case .screenRecording where model.screenRecording.opensSystemSettings: OnboardingStrings.quitAndReopenHint
        // What macOS will ask is in the confirmation row itself.
        default: nil
        }
    }
}
