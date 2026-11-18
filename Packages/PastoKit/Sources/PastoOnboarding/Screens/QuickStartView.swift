import PastoInput
import PastoUI
import SwiftUI

/// The welcome's last step: the few settings worth choosing before starting.
struct QuickStartView: View {
    @Bindable var model: QuickStartModel

    var body: some View {
        OnboardingStep(illustration: .quickStart, title: OnboardingStrings.quickStartTitle, subtitle: OnboardingStrings.quickStartSubtitle) {
            card
        } buttons: {
            Button(OnboardingStrings.finishAction, action: model.finish)
                .buttonStyle(PastoButtonStyle(.filled))
                .keyboardShortcut(.defaultAction)
        }
        .alert(OnboardingStrings.reduceHistoryTitle, isPresented: isConfirmingCapacity) {
            Button(OnboardingStrings.delete, action: model.historyCapacity.confirmPendingCapacity)
            Button(OnboardingStrings.cancel, role: .cancel, action: model.historyCapacity.discardPendingCapacity)
        } message: {
            Text(OnboardingStrings.reduceHistoryMessage)
        }
        .alert(OnboardingStrings.shortcutConflictTitle, isPresented: isShowingConflict, presenting: model.shortcutConflict) { _ in
            Button(OnboardingStrings.ok) {}
        } message: { conflict in
            Text(OnboardingStrings.message(for: conflict))
        }
    }

    private var card: some View {
        OnboardingCard {
            OnboardingRow(title: OnboardingStrings.openAtLoginTitle, subtitle: OnboardingStrings.openAtLoginSubtitle) {
                // The title is hidden, not absent: it is still what assistive technologies read.
                Toggle(OnboardingStrings.openAtLoginTitle, isOn: $model.opensAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            OnboardingRow(
                title: OnboardingStrings.shortcutTitle,
                subtitle: OnboardingStrings.shortcutSubtitle,
                note: model.shortcutNote
            ) {
                ShortcutRecorderField(
                    title: OnboardingStrings.shortcutTitle,
                    text: model.shortcutText,
                    hasShortcut: model.activationShortcut != nil,
                    isRecording: model.isRecordingShortcut,
                    clearLabel: OnboardingStrings.clearShortcut,
                    onToggleRecording: model.toggleShortcutRecording,
                    onClear: model.clearShortcut
                )
            }
            OnboardingRow(title: OnboardingStrings.historyTitle, subtitle: OnboardingStrings.historySubtitle, isLast: true) {
                historyControl
            }
        }
    }

    private var historyControl: some View {
        VStack(spacing: 0) {
            HistoryCapacitySlider(
                model: model.historyCapacity,
                accessibilityLabel: OnboardingStrings.historyTitle,
                unlimitedText: OnboardingStrings.unlimited
            )
            HStack(alignment: .top, spacing: OnboardingMetrics.sliderValueSymbolSpacing) {
                Text(HistoryCapacityText.value(forDays: model.historyCapacity.shownDays) ?? OnboardingStrings.unlimited)
                if model.historyCapacity.shownDays == 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .help(OnboardingStrings.unlimitedWarning)
                        .accessibilityLabel(OnboardingStrings.unlimitedWarning)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(width: OnboardingMetrics.sliderWidth)
    }

    /// An alert that goes away without a button leaves the limit as it was. It is put back a
    /// turn later, so a button's own action always runs first.
    private var isConfirmingCapacity: Binding<Bool> {
        Binding(
            get: { model.historyCapacity.pendingDays != nil },
            set: { isPresented in
                guard !isPresented else { return }
                Task { model.historyCapacity.discardPendingCapacity() }
            }
        )
    }

    private var isShowingConflict: Binding<Bool> {
        Binding(
            get: { model.shortcutConflict != nil },
            set: { if !$0 { model.shortcutConflict = nil } }
        )
    }
}
