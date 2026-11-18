import AppKit
import SwiftUI

/// Settings › General. There is no "Show in Menu Bar" row: since macOS 26 the menu bar icon is
/// shown or hidden from System Settings › Menu Bar.
struct GeneralPane: View {
    @Bindable var model: GeneralModel

    var body: some View {
        SettingsPaneLayout {
            SettingsSection {
                SettingsToggleRow(
                    title: SettingsStrings.openAtLogin,
                    isOn: Binding(get: { model.loginItem.isEnabled }, set: model.loginItem.setEnabled)
                ) {
                    if model.loginItem.isBlockedBySystem {
                        SettingsWarningPill(
                            title: SettingsStrings.allowInLoginItems,
                            action: model.loginItem.openSystemSettings
                        )
                        .help(SettingsStrings.loginItemBlocked)
                    }
                }
                SettingsToggleRow(title: SettingsStrings.soundEffects, isOn: model.isSoundEffectsEnabled.binding)
            }
            SettingsSection(title: SettingsStrings.pasteItemsTitle) {
                PasteDestinationPicker(model: model)
                Toggle(SettingsStrings.alwaysPastePlainText, isOn: model.isPasteAsPlainTextEnabled.binding)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HistorySection(model: model.history)
        }
    }
}

/// Where a chosen item goes: two exclusive options and, beside them, a picture of the one chosen.
/// Choosing only changes the setting; the permission is asked for from the pill alone.
private struct PasteDestinationPicker: View {
    @Bindable var model: GeneralModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Picker(SettingsStrings.pasteItemsTitle, selection: model.isDirectPasteEnabled.binding) {
                PasteDestinationOption(title: SettingsStrings.pasteToActiveApp, info: SettingsStrings.pasteToActiveAppInfo) {
                    if model.needsAccessibilityAccess {
                        SettingsWarningPill(
                            title: SettingsStrings.allowAccessibilityAccess,
                            action: model.requestAccessibilityAccess
                        )
                    }
                }
                .tag(true)
                PasteDestinationOption(title: SettingsStrings.pasteToClipboard, info: SettingsStrings.pasteToClipboardInfo) {}
                    .tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            // The pill sits inside an option, where VoiceOver does not reach it: the group
            // offers what it does as an action of its own.
            .accessibilityActions {
                if model.needsAccessibilityAccess {
                    Button(SettingsStrings.allowAccessibilityAccess, action: model.requestAccessibilityAccess)
                }
            }
            Spacer()
            PasteDestinationIllustration(symbolName: model.isDirectPasteEnabled.value ? "macwindow" : "clipboard")
        }
    }
}

private struct PasteDestinationOption<Accessory: View>: View {
    let title: String
    let info: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSubtitleSpacing) {
            Text(title)
            Text(info)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            accessory
        }
    }
}

/// A picture of a paste destination: its symbol on a tinted ground.
private struct PasteDestinationIllustration: View {
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: SettingsMetrics.illustrationSymbolPointSize))
            .foregroundStyle(.tint)
            .frame(width: SettingsMetrics.illustrationSize.width, height: SettingsMetrics.illustrationSize.height)
            .background(.tint.opacity(SettingsMetrics.illustrationBackdropOpacity))
            .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.illustrationCornerRadius))
            .accessibilityHidden(true)
    }
}
