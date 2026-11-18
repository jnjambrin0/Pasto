import SwiftUI

/// A row of a section: what the setting is on the leading side, its control on the trailing one,
/// both from the top. Under the title and the subtitle there may be an accessory, such as a pill
/// saying what the setting still needs.
struct SettingsRow<Control: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRowLabel(title: title, subtitle: subtitle)
                accessory
            }
            Spacer()
            control
                .frame(maxHeight: SettingsMetrics.rowControlMaxHeight)
        }
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.init(title: title, subtitle: subtitle, control: control, accessory: { EmptyView() })
    }
}

/// A row whose control is a switch.
struct SettingsToggleRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    @ViewBuilder var accessory: Accessory

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            // The title is hidden, not absent: it is still what assistive technologies read.
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        } accessory: {
            accessory
        }
    }
}

extension SettingsToggleRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.init(title: title, subtitle: subtitle, isOn: isOn, accessory: { EmptyView() })
    }
}

/// A title and, under it, a secondary line saying more.
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSubtitleSpacing) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
