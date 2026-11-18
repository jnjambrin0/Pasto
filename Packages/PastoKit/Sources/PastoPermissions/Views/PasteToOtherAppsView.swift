import SwiftUI

/// Asked when an item is chosen for pasting and Pasto has no Accessibility access: grant it, or
/// only copy the item.
struct PasteToOtherAppsView: View {
    /// The application the paste would go to; nil when it has no name to show.
    let applicationName: String?
    let onFinish: (PasteToOtherAppsResult) -> Void

    @State private var doNotAskAgain = false

    var body: some View {
        VStack(spacing: 0) {
            // Runs to the window's edges.
            PermissionIllustration(.accessibility, cornerRadius: 0)
                .frame(height: PermissionMetrics.promptIllustrationHeight)
            VStack(spacing: PermissionMetrics.promptBlockSpacing) {
                VStack(spacing: PermissionMetrics.promptTextSpacing) {
                    Text(PermissionStrings.pasteToOtherAppsTitle(applicationName ?? PermissionStrings.currentApplication))
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(PermissionStrings.pasteToOtherAppsDescription)
                        .font(.body)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: PermissionMetrics.promptControlSpacing) {
                    VStack(spacing: PermissionMetrics.promptButtonSpacing) {
                        Button {
                            onFinish(.enableAccessibilityAccess)
                        } label: {
                            Text(PermissionStrings.allowAccessibilityAccess).frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut(.defaultAction)
                        Button {
                            onFinish(.copyToClipboard(doNotAskAgain: doNotAskAgain))
                        } label: {
                            Text(PermissionStrings.copyToClipboard).frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Toggle(PermissionStrings.doNotAskAgain, isOn: $doNotAskAgain)
                }
            }
            .padding([.horizontal, .bottom], PermissionMetrics.promptBlockInset)
        }
        .frame(width: PermissionMetrics.promptWidth)
    }
}
