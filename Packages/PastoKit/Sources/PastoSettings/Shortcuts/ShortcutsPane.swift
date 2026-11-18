import AppKit
import PastoInput
import PastoUI
import SwiftUI

/// Settings › Shortcuts.
struct ShortcutsPane: View {
    @Bindable var model: ShortcutsModel

    var body: some View {
        SettingsPaneLayout {
            SettingsSection {
                recorderRow(.activation)
                recorderRow(.pasteStack)
            }
            SettingsSection {
                recorderRow(.nextPinboard)
                recorderRow(.previousPinboard)
            }
            SettingsSection {
                SettingsRow(title: SettingsStrings.quickPaste) {
                    HStack {
                        ModifierPullDown(
                            title: SettingsStrings.quickPaste,
                            options: ModifierChoice.quickPasteOptions,
                            selection: $model.quickPasteModifier
                        )
                        // The digits the modifier goes with; the same in every language.
                        Text(verbatim: "+ 1...9")
                    }
                }
                SettingsRow(title: SettingsStrings.plainTextMode) {
                    ModifierPullDown(
                        title: SettingsStrings.plainTextMode,
                        options: ModifierChoice.plainTextOptions,
                        selection: $model.plainTextModifier
                    )
                }
            }
            HStack {
                Spacer()
                Button(SettingsStrings.resetShortcuts) { model.isConfirmingReset = true }
            }
        }
        .confirmationDialog(
            SettingsStrings.resetShortcutsConfirmation,
            isPresented: $model.isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button(SettingsStrings.reset, action: model.restoreDefaults)
            Button(SettingsStrings.cancel, role: .cancel) {}
        }
        .alert(SettingsStrings.shortcutConflictTitle, isPresented: isShowingConflict, presenting: model.conflict) { _ in
            Button(SettingsStrings.ok) {}
        } message: { conflict in
            Text(SettingsStrings.message(for: conflict))
        }
    }

    private func recorderRow(_ field: ShortcutField) -> some View {
        SettingsRow(title: field.title) {
            ShortcutRecorderField(
                title: field.title,
                text: model.recorderText(for: field),
                hasShortcut: model.shortcut(for: field) != nil,
                isRecording: model.recordingField == field,
                clearLabel: SettingsStrings.clearShortcut,
                onToggleRecording: { model.toggleRecording(field) },
                onClear: { model.setShortcut(nil, for: field) }
            )
        }
    }

    private var isShowingConflict: Binding<Bool> {
        Binding(
            get: { model.conflict != nil },
            set: { if !$0 { model.conflict = nil } }
        )
    }
}

/// A menu that shows the chosen modifier and offers the others: no button around it, only a
/// small chevron box after the name.
private struct ModifierPullDown: View {
    let title: String
    let options: [ModifierChoice]
    @Binding var selection: ModifierChoice

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: SettingsMetrics.modifierLabelSpacing) {
                Text(selection.title)
                // The colours of a pop-up button's chevron.
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: SettingsMetrics.modifierChevronPointSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: SettingsMetrics.modifierChevronBoxSide, height: SettingsMetrics.modifierChevronBoxSide)
                    .background(.tint, in: RoundedRectangle(cornerRadius: SettingsMetrics.modifierChevronCornerRadius))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(selection.title)
    }
}
