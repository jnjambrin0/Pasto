import AppKit
import Observation
import PastoCore
import PastoFoundation

/// The state behind the General pane.
@Observable
final class GeneralModel {
    let loginItem = LoginItem()
    let isSoundEffectsEnabled: Setting<Bool>
    let isDirectPasteEnabled: Setting<Bool>
    let isPasteAsPlainTextEnabled: Setting<Bool>
    let accessibility: AccessibilityMonitor
    let history: HistoryModel
    private let presentAccessibilityAccess: () -> Void

    init(environment: SettingsEnvironment, accessibility: AccessibilityMonitor, isDirectPasteEnabled: Setting<Bool>) {
        let config = environment.config
        isSoundEffectsEnabled = Setting(.isSoundEffectsEnabled, in: config)
        isPasteAsPlainTextEnabled = Setting(.isPasteAsPlainTextEnabled, in: config)
        self.isDirectPasteEnabled = isDirectPasteEnabled
        self.accessibility = accessibility
        history = HistoryModel(
            reader: environment.reader,
            writer: environment.writer,
            didChangeItemsIrreversibly: environment.didChangeItemsIrreversibly,
            didEraseHistory: environment.didEraseHistory
        )
        presentAccessibilityAccess = environment.requestAccessibilityAccess
    }

    /// Direct paste is chosen but cannot work without the permission.
    var needsAccessibilityAccess: Bool {
        isDirectPasteEnabled.value && !accessibility.isGranted
    }

    /// The permission's window is modal: with another modal window up, Pasto only comes forward.
    func requestAccessibilityAccess() {
        guard NSApp.modalWindow == nil else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        presentAccessibilityAccess()
    }
}
