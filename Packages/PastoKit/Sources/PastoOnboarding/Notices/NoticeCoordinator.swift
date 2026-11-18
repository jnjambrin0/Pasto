import AppKit
import os
import PastoCore
import PastoFoundation
import PastoPermissions
import PastoUI

/// Decides which notice cards are on show: seeds them when onboarding ends, takes each away
/// once what it suggests is done, and does what their buttons ask.
public final class NoticeCoordinator {
    private let repository: NoticeRepository
    private let config: ConfigStore
    private let permissions: SystemPermissionsPresenter
    private let loginItem = LoginItemService()
    private let log = Log.logger(.app)
    private var observations: [Task<Void, Never>] = []
    private var pasteboardAccessReminder = PasteboardAccessReminder()
    /// Whether capture last found pasteboard access missing; nil until it has tried. A card
    /// from an earlier launch may still be on show meanwhile.
    private var isPasteboardAccessMissing: Bool?
    private var storeWriteFailures = StoreWriteFailureStreak()
    /// Whether saving last kept failing, which put up the card; nil until a write has been
    /// saved or failed, while a card from an earlier launch may still be on show. A card the
    /// user closed stays closed until saving works again and fails anew.
    private var isStoreWriteFailing: Bool?

    /// The name of a card's close button, for the view that shows the cards.
    public nonisolated static var closeButtonLabel: String {
        OnboardingStrings.closeNotice
    }

    /// What the button of the card about taken shortcuts does: open Settings › Shortcuts.
    public var openShortcutSettings: () -> Void = {}

    public init(repository: NoticeRepository, config: ConfigStore, permissions: SystemPermissionsPresenter) {
        self.repository = repository
        self.config = config
        self.permissions = permissions
    }

    isolated deinit {
        observations.forEach { $0.cancel() }
    }

    /// Call once, when onboarding has just finished.
    public func seedAfterOnboarding() {
        let cards = NoticeCatalog.cardsAfterOnboarding(
            isLoginItemEnabled: loginItem.isEnabled,
            isDirectPasteEnabled: config.value(for: .isDirectPasteEnabled),
            otherClipboardManagers: KnownClipboardManager.running().map(\.name)
        )
        cards.forEach(repository.add)
    }

    /// Starts taking cards away as the user turns on what they suggest, wherever that happens.
    public func start() {
        guard observations.isEmpty else { return }
        if PasteboardAccess.isAlwaysAllowed {
            repository.remove(id: NoticeCatalog.pasteboardAccess.id)
        }
        observations = [
            Task { [repository, loginItem] in
                for await isEnabled in loginItem.changes() where isEnabled {
                    repository.remove(id: NoticeCatalog.openAtLogin.id)
                }
            },
            Task { [repository, config] in
                // The first value is the setting as it stands, which is what seeded the card.
                for await isEnabled in config.values(for: .isDirectPasteEnabled).dropFirst() where isEnabled {
                    repository.remove(id: NoticeCatalog.enableDirectPaste.id)
                }
            },
        ]
    }

    // MARK: - Shortcuts

    /// At launch: the user's system-wide shortcuts that something else answers to now, as
    /// shown ("⇧⌘V"). A card says so until a launch finds none; one the user closed comes back
    /// at the next launch that still finds them.
    public func shortcutsAreTaken(_ shortcuts: [String]) {
        // Removed first, so that the card names the shortcuts of this launch.
        repository.remove(id: NoticeCatalog.shortcutsTakenID)
        if let card = NoticeCatalog.shortcutsTaken(shortcuts) {
            repository.add(card)
        }
    }

    // MARK: - Saving

    /// A write to the store failed — a capture, a change made in the panel. From the third in a
    /// row a card says that what is copied is not being saved.
    public func storeWriteDidFail() {
        guard storeWriteFailures.writeDidFail(), isStoreWriteFailing != true else { return }
        isStoreWriteFailing = true
        log.error("Writes to the store keep failing: showing the notice card")
        repository.add(NoticeCatalog.storeWriteFailure)
    }

    /// A write to the store was saved: the card, if any, goes away.
    public func storeWriteDidSucceed() {
        storeWriteFailures.writeDidSucceed()
        guard isStoreWriteFailing != false else { return }
        isStoreWriteFailing = false
        repository.remove(id: NoticeCatalog.storeWriteFailure.id)
    }

    // MARK: - Pasteboard access

    /// Capture could not read the pasteboard: access is short of "always allow" and nothing
    /// copied is saved. The card goes up when access is first found missing — in this launch,
    /// or after it worked — so a card the user closed stays closed meanwhile; the modal window
    /// that asks for access, only as `PasteboardAccessReminder` allows.
    public func pasteboardAccessIsMissing(isPanelOpen: Bool) {
        if isPasteboardAccessMissing != true {
            isPasteboardAccessMissing = true
            repository.add(NoticeCatalog.pasteboardAccess)
        }
        let shouldAsk = pasteboardAccessReminder.shouldAsk(
            isDenied: PasteboardAccess.current == .alwaysDenied,
            isPanelOpen: isPanelOpen,
            isModalWindowUp: NSApp.modalWindow != nil
        )
        guard shouldAsk else { return }
        // The window is modal: shown from here it would hold up the capture events.
        Task { [weak self] in
            guard NSApp.modalWindow == nil else { return }
            self?.requestPasteboardAccess()
        }
    }

    /// Capture read the pasteboard: the card, if any, has nothing left to ask.
    public func pasteboardAccessIsWorking() {
        guard isPasteboardAccessMissing != false else { return }
        isPasteboardAccessMissing = false
        repository.remove(id: NoticeCatalog.pasteboardAccess.id)
    }

    private func requestPasteboardAccess() {
        if permissions.requestPasteboardAccess() == .success {
            repository.remove(id: NoticeCatalog.pasteboardAccess.id)
        }
    }

    // MARK: - Buttons

    /// Does what a card's button asks. The card goes away through `start()`'s observations.
    public func perform(_ command: NoticeCard.Command) {
        switch command {
        case .enableOpenAtLogin:
            enableOpenAtLogin()
        case .enableDirectPaste:
            enableDirectPaste()
        case .allowPasteboardAccess:
            guard NSApp.modalWindow == nil else {
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            requestPasteboardAccess()
        case .acknowledgeOtherClipboardManagers:
            repository.remove(id: NoticeCatalog.otherClipboardManagersID)
        case .openShortcutSettings:
            openShortcutSettings()
        case .openStorageSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// When macOS refuses the login item, or registers it but waits for the user to approve it,
    /// the user is taken to System Settings › General › Login Items. The card stays until the
    /// item is enabled.
    private func enableOpenAtLogin() {
        do {
            try loginItem.setEnabled(true)
        } catch {
            log.error("Could not register the login item: \(error)")
        }
        guard loginItem.isEnabled else {
            log.info("The login item is \(String(describing: self.loginItem.status), privacy: .public): opening System Settings")
            LoginItemService.openSystemSettings()
            return
        }
        OSD.show(symbol: "checkmark", title: OnboardingStrings.enabled)
    }

    /// Direct paste is no use without Accessibility access, so that comes first.
    private func enableDirectPaste() {
        if !AccessibilityAccess.isGranted {
            guard NSApp.modalWindow == nil else {
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            guard permissions.requestAccessibilityAccess() == .success else { return }
        }
        config.set(true, for: .isDirectPasteEnabled)
    }
}
