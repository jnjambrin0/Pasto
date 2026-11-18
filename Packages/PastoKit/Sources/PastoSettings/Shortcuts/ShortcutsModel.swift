import AppKit
import Observation
import PastoFoundation
import PastoInput

/// The state behind the Shortcuts pane, including the recording of a shortcut.
@Observable
final class ShortcutsModel {
    /// The field that is listening for a key combination, if any.
    private(set) var recordingField: ShortcutField?
    var isConfirmingReset = false

    private let config: ConfigStore
    private let shortcuts: [ShortcutField: Setting<JSONConfigValue<Shortcut?>>]
    private let quickPasteFlags: Setting<Int>
    private let plainTextFlags: Setting<Int>
    private let recorder: ShortcutRecorder

    init(environment: SettingsEnvironment) {
        config = environment.config
        recorder = ShortcutRecorder(hotKeys: environment.hotKeys)
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutField.allCases.map { ($0, Setting($0.key, in: environment.config)) })
        quickPasteFlags = Setting(.quickPasteModifierFlags, in: config)
        plainTextFlags = Setting(.plainTextModifierFlags, in: config)
    }

    // MARK: - Shortcuts

    func shortcut(for field: ShortcutField) -> Shortcut? {
        shortcuts[field]?.value.value
    }

    func setShortcut(_ shortcut: Shortcut?, for field: ShortcutField) {
        config.setShortcut(shortcut, for: field.key)
    }

    /// What the field shows: its shortcut, or the progress of the recording.
    func recorderText(for field: ShortcutField) -> String {
        ShortcutDisplay.recorderText(
            for: shortcut(for: field),
            recorder: recordingField == field ? recorder : nil,
            recordingPlaceholder: SettingsStrings.recording,
            emptyPlaceholder: SettingsStrings.noShortcut,
            spaceKeyName: SettingsStrings.spaceKey
        )
    }

    func restoreDefaults() {
        recorder.cancel()
        ShortcutDefaults.restore(in: config)
    }

    // MARK: - Modifiers

    var quickPasteModifier: ModifierChoice {
        get {
            ModifierChoice.selection(
                forStoredFlags: quickPasteFlags.value,
                among: ModifierChoice.quickPasteOptions,
                default: ConfigKey.quickPasteModifierFlags.defaultValue
            )
        }
        set { quickPasteFlags.value = newValue.storedFlags }
    }

    var plainTextModifier: ModifierChoice {
        get {
            ModifierChoice.selection(
                forStoredFlags: plainTextFlags.value,
                among: ModifierChoice.plainTextOptions,
                default: ConfigKey.plainTextModifierFlags.defaultValue
            )
        }
        set { plainTextFlags.value = newValue.storedFlags }
    }

    // MARK: - Recording

    /// Why the last combination could not be recorded, until the user has read it.
    var conflict: ShortcutConflict? {
        get { recorder.conflict }
        set { recorder.conflict = newValue }
    }

    /// A click on a field: start listening, or stop if it already was.
    func toggleRecording(_ field: ShortcutField) {
        let wasRecording = recordingField == field
        recorder.cancel()
        guard !wasRecording else { return }
        recordingField = field
        recorder.start(otherShortcuts: otherShortcuts(than: field)) { [weak self] ending in
            guard let self else { return }
            recordingField = nil
            switch ending {
            case .recorded(let shortcut): setShortcut(shortcut, for: field)
            case .cleared: setShortcut(nil, for: field)
            case .cancelled: break
            }
            ShortcutRecorder.announce(
                config.shortcut(for: field.key).map { ShortcutDisplay.string(for: $0) } ?? SettingsStrings.noShortcut
            )
        }
        ShortcutRecorder.announce(SettingsStrings.recording)
    }

    /// The other fields that have a shortcut, named after their rows, and the Paste Stack's fixed
    /// "Paste All".
    private func otherShortcuts(than field: ShortcutField) -> [NamedShortcut] {
        let fields = ShortcutField.allCases.filter { $0 != field }.compactMap { other in
            shortcut(for: other).map { NamedShortcut(name: other.title, shortcut: $0) }
        }
        return fields + [.pasteStackPasteAll(name: SettingsStrings.pasteStackPasteAll)]
    }
}
