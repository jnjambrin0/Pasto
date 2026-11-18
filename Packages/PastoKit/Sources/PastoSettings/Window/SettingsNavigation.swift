import Observation

/// The pane on show: the sidebar changes it when a pane is clicked, the window when the app asks
/// for a pane (Help › Keyboard Shortcuts).
@Observable
final class SettingsNavigation {
    var selection: SettingsPane = .general
}
