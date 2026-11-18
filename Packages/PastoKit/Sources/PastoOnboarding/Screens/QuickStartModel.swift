import Observation
import os
import PastoCore
import PastoFoundation
import PastoInput
import PastoUI

/// The state behind the Quick Start screen. The switch and the shortcut take effect when the
/// user goes on; the history capacity, as the slider is let go.
@Observable
final class QuickStartModel {
    /// On a first launch, on — unless this copy runs from somewhere that goes away, a disk image
    /// or where macOS translocated a download, because the user chose not to move it: a login
    /// item there would point at nothing next time. Shown again from the Help menu, as it is
    /// (`loadLoginItemState`).
    var opensAtLogin: Bool
    private(set) var activationShortcut: Shortcut?
    /// The shortcut the screen opened with: what launch chose for a new installation.
    private let initialActivationShortcut: Shortcut?
    let historyCapacity: HistoryCapacityModel

    private let config: ConfigStore
    private let recorder: ShortcutRecorder
    private let onContinue: () -> Void
    private let log = Log.logger(.app)
    /// Registering or removing the login item, once the user has gone on.
    @ObservationIgnored private(set) var loginItemUpdate: Task<Void, Never>?

    init(
        config: ConfigStore,
        reader: StoreReader,
        writer: StoreWriter,
        hotKeys: HotKeyCenter,
        onContinue: @escaping () -> Void
    ) {
        self.config = config
        opensAtLogin = !ApplicationLocation.current().isEphemeral
        self.onContinue = onContinue
        recorder = ShortcutRecorder(hotKeys: hotKeys)
        let activationShortcut = config.shortcut(for: .activationShortcut)
        self.activationShortcut = activationShortcut
        initialActivationShortcut = activationShortcut
        historyCapacity = HistoryCapacityModel(storage: HistoryCapacityModel.Storage(
            days: { reader.historyCapacity.days },
            expiredItemCount: { reader.expiredHistoryItemCount(for: HistoryCapacity(days: $0)) },
            setDays: { days in
                try await writer.perform(author: .user) { _ = try $0.setHistoryCapacity(HistoryCapacity(days: days)) }
            }
        ))
    }

    // MARK: - Activation shortcut

    var isRecordingShortcut: Bool {
        recorder.isRecording
    }

    var shortcutText: String {
        ShortcutDisplay.recorderText(
            for: activationShortcut,
            recorder: recorder,
            recordingPlaceholder: OnboardingStrings.recordingShortcut,
            emptyPlaceholder: OnboardingStrings.noShortcut,
            spaceKeyName: OnboardingStrings.spaceKey
        )
    }

    /// Why the shortcut is not ⇧⌘V, while it is still the one launch chose: another app has
    /// ⇧⌘V (and, with no shortcut at all, ⌃⇧⌘V too). Nil once the user records their own.
    var shortcutNote: String? {
        guard activationShortcut == initialActivationShortcut, !recorder.isRecording else { return nil }
        return Self.note(for: activationShortcut, shortcutText: { ShortcutDisplay.string(for: $0) })
    }

    nonisolated static func note(for shortcut: Shortcut?, shortcutText: (Shortcut) -> String) -> String? {
        switch shortcut {
        case ShortcutDefaults.alternateActivation:
            OnboardingStrings.shortcutTakenNote(shortcutText(ShortcutDefaults.activation))
        case nil:
            OnboardingStrings.shortcutsTakenNote(
                shortcutText(ShortcutDefaults.activation),
                shortcutText(ShortcutDefaults.alternateActivation)
            )
        default:
            nil
        }
    }

    /// Why the last combination could not be recorded, until the user has read it.
    var shortcutConflict: ShortcutConflict? {
        get { recorder.conflict }
        set { recorder.conflict = newValue }
    }

    func toggleShortcutRecording() {
        guard !recorder.isRecording else {
            recorder.cancel()
            return
        }
        recorder.start(otherShortcuts: otherShortcuts) { [weak self] ending in
            switch ending {
            case .recorded(let shortcut): self?.activationShortcut = shortcut
            case .cleared: self?.activationShortcut = nil
            case .cancelled: break
            }
            ShortcutRecorder.announce(
                self?.activationShortcut.map { ShortcutDisplay.string(for: $0) } ?? OnboardingStrings.noShortcut
            )
        }
        ShortcutRecorder.announce(OnboardingStrings.recordingShortcut)
    }

    func clearShortcut() {
        activationShortcut = nil
    }

    /// The shortcuts Pasto uses for something else, which cannot open the panel as well.
    private var otherShortcuts: [NamedShortcut] {
        let settings: [(ShortcutKey, String)] = [
            (.pasteStackShortcut, OnboardingStrings.pasteStackShortcutName),
            (.nextPinboardShortcut, OnboardingStrings.nextPinboardShortcutName),
            (.previousPinboardShortcut, OnboardingStrings.previousPinboardShortcutName),
        ]
        let named = settings.compactMap { key, name in
            config.shortcut(for: key).map { NamedShortcut(name: name, shortcut: $0) }
        }
        return named + [.pasteStackPasteAll(name: OnboardingStrings.pasteStackPasteAllName)]
    }

    // MARK: - Going on

    /// Applies the switch and the shortcut and goes on. The login item is registered off the
    /// main thread — `SMAppService` waits on a system daemon — so the window answers at once;
    /// the welcome waits for it before it hands over to the panel.
    func finish() {
        recorder.cancel()
        config.setShortcut(activationShortcut, for: .activationShortcut)
        let opensAtLogin = opensAtLogin
        loginItemUpdate = Task.detached(priority: .userInitiated) { [log] in
            do {
                try LoginItemService().setEnabled(opensAtLogin)
            } catch {
                log.error("Could not \(opensAtLogin ? "register" : "unregister", privacy: .public) the login item: \(error)")
            }
        }
        onContinue()
    }

    /// Shown again from the Help menu, the switch shows how things are, which the system is
    /// asked for off the main thread while the earlier steps are on show.
    func loadLoginItemState() {
        Task { [weak self] in
            let isEnabled = await Task.detached(priority: .userInitiated) { LoginItemService().isEnabled }.value
            self?.opensAtLogin = isEnabled
        }
    }
}
