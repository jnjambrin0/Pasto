import SwiftUI

/// The frame every pane shares: its sections stacked at the pane's fixed width, with a margin on
/// both sides and at the bottom but none at the top, where the header stands. The width is set
/// here, not by the window, so that the pane reports the height it needs at that width.
struct SettingsPaneLayout<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            content
        }
        .padding(.horizontal, SettingsMetrics.paneHorizontalInset)
        .padding(.bottom, SettingsMetrics.paneBottomInset)
        .frame(width: SettingsMetrics.contentWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
