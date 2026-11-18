import AppKit

/// The confirmations the panel asks for before it deletes.
enum PanelAlert {
    /// An application-modal alert with an action and Cancel; true when the action was chosen.
    /// The action is the first button, so Return confirms; it is never styled as destructive.
    /// The panel stays open behind the alert and takes the keyboard back afterwards.
    static func confirm(title: String, message: String? = nil, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        if let message {
            alert.informativeText = message
        }
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: ToolbarStrings.cancel)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
