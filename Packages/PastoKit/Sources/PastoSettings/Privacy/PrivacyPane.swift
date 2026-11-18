import PastoCore
import SwiftUI

/// Settings › Privacy.
struct PrivacyPane: View {
    @Bindable var model: PrivacyModel
    /// Removes all of Pasto's data and quits; nil leaves the row out.
    var removeAllData: (() -> Void)?
    @State private var isConfirmingRemoval = false

    var body: some View {
        SettingsPaneLayout {
            VStack(spacing: SettingsMetrics.switchBoxSpacing) {
                SettingsSection {
                    SettingsToggleRow(
                        title: SettingsStrings.showDuringScreenSharing,
                        subtitle: SettingsStrings.showDuringScreenSharingInfo,
                        isOn: model.isScreenSharingContentVisible.binding
                    )
                    SettingsToggleRow(
                        title: SettingsStrings.generateLinkPreviews,
                        subtitle: SettingsStrings.generateLinkPreviewsInfo,
                        isOn: model.isLinkPreviewsEnabled.binding
                    )
                }
                SettingsSection {
                    SettingsToggleRow(
                        title: SettingsStrings.ignoreConfidentialContent,
                        subtitle: SettingsStrings.ignoreConfidentialContentInfo,
                        isOn: isIgnored(.confidential)
                    )
                    SettingsToggleRow(
                        title: SettingsStrings.ignoreTransientContent,
                        subtitle: SettingsStrings.ignoreTransientContentInfo,
                        isOn: isIgnored(.transient)
                    )
                }
            }
            SettingsSection(
                title: SettingsStrings.ignoreApplicationsTitle,
                subtitle: SettingsStrings.ignoreApplicationsInfo,
                isPadded: false
            ) {
                IgnoredApplicationsList(
                    applications: model.applications,
                    selection: $model.selectedApplications,
                    onDelete: model.removeSelectedApplications
                )
                HStack(spacing: 0) {
                    listButton("plus", SettingsStrings.addApplication, action: model.chooseApplications)
                    Divider()
                    listButton("minus", SettingsStrings.removeApplication, action: model.removeSelectedApplications)
                        .disabled(model.selectedApplications.isEmpty)
                    Spacer()
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let removeAllData {
                SettingsSection {
                    SettingsRow(title: SettingsStrings.removeAllData, subtitle: SettingsStrings.removeAllDataInfo) {
                        Button(SettingsStrings.removeAllDataButton) { isConfirmingRemoval = true }
                    }
                }
                .alert(SettingsStrings.removeAllDataTitle, isPresented: $isConfirmingRemoval) {
                    Button(SettingsStrings.removeAllDataConfirm, role: .destructive, action: removeAllData)
                    Button(SettingsStrings.cancel, role: .cancel) {}
                } message: {
                    Text(SettingsStrings.removeAllDataMessage)
                }
            }
        }
    }

    private func isIgnored(_ type: IgnoredContentType) -> Binding<Bool> {
        Binding(get: { model.isIgnored(type) }, set: { model.setIgnored($0, type) })
    }

    private func listButton(_ symbolName: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .frame(width: SettingsMetrics.listButtonSize, height: SettingsMetrics.listButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The ignored applications that are installed, as a list as tall as its rows, which never
/// scrolls. The Delete key takes the selected ones off.
private struct IgnoredApplicationsList: View {
    let applications: [IgnoredApplication]
    @Binding var selection: Set<IgnoredApplication.ID>
    let onDelete: () -> Void

    var body: some View {
        if applications.isEmpty {
            Text(SettingsStrings.noApplications)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: SettingsMetrics.emptyApplicationListMinHeight)
        } else {
            List(applications, selection: $selection) { application in
                HStack {
                    Image(nsImage: application.icon)
                        .resizable()
                        .frame(width: SettingsMetrics.applicationIconSize, height: SettingsMetrics.applicationIconSize)
                    Text(application.name)
                        .lineLimit(1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .environment(\.defaultMinListRowHeight, SettingsMetrics.applicationRowHeight)
            .frame(height: CGFloat(applications.count) * SettingsMetrics.applicationRowHeight)
            .onDeleteCommand(perform: onDelete)
        }
    }
}
