import PastoInput

/// The shortcuts the user can record, in the order the pane lists them.
enum ShortcutField: CaseIterable, Identifiable {
    case activation
    case pasteStack
    case nextPinboard
    case previousPinboard

    var id: Self { self }

    var key: ShortcutKey {
        switch self {
        case .activation: .activationShortcut
        case .pasteStack: .pasteStackShortcut
        case .nextPinboard: .nextPinboardShortcut
        case .previousPinboard: .previousPinboardShortcut
        }
    }

    var title: String {
        switch self {
        case .activation: SettingsStrings.activatePasto
        case .pasteStack: SettingsStrings.activatePasteStack
        case .nextPinboard: SettingsStrings.showNextPinboard
        case .previousPinboard: SettingsStrings.showPreviousPinboard
        }
    }
}
