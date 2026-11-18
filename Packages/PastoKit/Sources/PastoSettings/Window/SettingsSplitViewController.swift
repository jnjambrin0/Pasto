import AppKit
import PastoCore
import PastoFoundation
import SwiftUI

/// The window's content: a fixed sidebar that lists the panes and, next to it, the pane itself.
final class SettingsSplitViewController: NSSplitViewController {
    private let navigation = SettingsNavigation()
    private let panes: [SettingsPane]
    private var showPane: (SettingsPane) -> Void = { _ in }

    init(environment: SettingsEnvironment) {
        panes = environment.panes
        super.init(nibName: nil, bundle: nil)

        // Shared by the General pane and by the sidebar's badge for it.
        let accessibility = AccessibilityMonitor()
        let isDirectPasteEnabled = Setting(.isDirectPasteEnabled, in: environment.config)
        let paneContainer = PaneContainerViewController { pane in
            switch pane {
            case .general:
                AnyView(GeneralPane(model: GeneralModel(
                    environment: environment, accessibility: accessibility, isDirectPasteEnabled: isDirectPasteEnabled
                )))
            case .intelligence:
                AnyView(IntelligencePane(model: IntelligenceModel(
                    config: environment.config, suggestions: environment.suggestions
                )))
            case .privacy:
                AnyView(PrivacyPane(model: PrivacyModel(config: environment.config), removeAllData: environment.removeAllData))
            case .shortcuts:
                AnyView(ShortcutsPane(model: ShortcutsModel(environment: environment)))
            }
        }
        let sidebar = NSHostingController(rootView: SidebarView(
            panes: environment.panes,
            accessibility: accessibility,
            isDirectPasteEnabled: isDirectPasteEnabled,
            isScreenAccessMissing: environment.suggestions.isScreenAccessMissing,
            navigation: navigation,
            onSelect: { [weak paneContainer] in paneContainer?.show($0) }
        ))
        showPane = { [weak paneContainer] in paneContainer?.show($0) }

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = SettingsMetrics.sidebarWidth
        sidebarItem.maximumThickness = SettingsMetrics.sidebarWidth
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)

        let contentItem = NSSplitViewItem(viewController: paneContainer)
        contentItem.minimumThickness = SettingsMetrics.contentWidth
        contentItem.maximumThickness = SettingsMetrics.contentWidth
        addSplitViewItem(contentItem)
    }

    /// Shows `pane` and selects it in the sidebar. A pane this Mac does not list is ignored.
    func select(_ pane: SettingsPane) {
        guard panes.contains(pane) else { return }
        navigation.selection = pane
        showPane(pane)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
