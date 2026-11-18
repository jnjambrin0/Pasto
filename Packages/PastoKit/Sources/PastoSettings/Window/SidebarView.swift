import PastoFoundation
import SwiftUI

/// The list of panes. A pane is flagged while something it sets cannot work: General while direct
/// paste is on without Accessibility access, Intelligence while suggestions are on without screen
/// recording access.
struct SidebarView: View {
    let panes: [SettingsPane]
    let accessibility: AccessibilityMonitor
    let isDirectPasteEnabled: Setting<Bool>
    let isScreenAccessMissing: () -> Bool
    let navigation: SettingsNavigation
    let onSelect: (SettingsPane) -> Void

    var body: some View {
        // Read here, so that a pane chosen from outside (Help › Keyboard Shortcuts) redraws the
        // list with it selected.
        let selection = navigation.selection
        List(selection: selectedPane(selection)) {
            ForEach(panes) { pane in
                HStack {
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbolName)
                            .font(.system(size: SettingsMetrics.sidebarIconPointSize))
                    }
                    Spacer()
                    if let badgeLabel = attentionLabel(for: pane) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: SettingsMetrics.sidebarBadgePointSize, weight: .bold))
                            .foregroundStyle(.red)
                            .accessibilityLabel(badgeLabel)
                    }
                }
                .tag(pane)
            }
        }
        // Pulled up into the room the sidebar list leaves under the title bar on macOS 26 and
        // later.
        .padding(.top, SettingsMetrics.sidebarListTopPadding)
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, SettingsMetrics.sidebarRowHeight)
    }

    /// A list selection is optional; ignoring "nothing" keeps one pane selected at all times.
    private func selectedPane(_ selection: SettingsPane) -> Binding<SettingsPane?> {
        Binding(
            get: { selection },
            set: { pane in
                guard let pane, pane != navigation.selection else { return }
                navigation.selection = pane
                onSelect(pane)
            }
        )
    }

    /// What the pane's badge stands for, or nil when it has none.
    private func attentionLabel(for pane: SettingsPane) -> String? {
        switch pane {
        case .general where isDirectPasteEnabled.value && !accessibility.isGranted:
            SettingsStrings.allowAccessibilityAccess
        case .intelligence where isScreenAccessMissing():
            SettingsStrings.allowScreenAccess
        default:
            nil
        }
    }
}
