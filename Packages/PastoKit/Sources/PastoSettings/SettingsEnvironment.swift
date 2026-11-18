import PastoCore
import PastoFoundation
import PastoInput

/// What the panes work with, handed down from the app.
struct SettingsEnvironment {
    let config: ConfigStore
    let reader: StoreReader
    let writer: StoreWriter
    let hotKeys: HotKeyCenter
    let requestAccessibilityAccess: () -> Void
    /// The user erased or shortened the history, which cannot be undone.
    var didChangeItemsIrreversibly: () -> Void = {}
    var didEraseHistory: () -> Void = {}
    /// Removes all of Pasto's data and quits, once the user has confirmed it. Without it, the
    /// Privacy pane does not offer it.
    var removeAllData: (() -> Void)?
    var suggestions = SuggestionsAvailability.unsupported

    /// The panes the sidebar lists.
    var panes: [SettingsPane] {
        SettingsPane.listed(hasSuggestions: suggestions.isSupported)
    }
}
