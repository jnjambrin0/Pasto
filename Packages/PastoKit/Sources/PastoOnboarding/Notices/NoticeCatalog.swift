import Foundation
import PastoUI

/// The notice cards Pasto can show.
nonisolated enum NoticeCatalog {
    static var openAtLogin: NoticeCard {
        NoticeCard(
            id: "openAtLogin",
            symbol: "power",
            title: OnboardingStrings.openAtLoginNoticeTitle,
            description: OnboardingStrings.openAtLoginNoticeDescription,
            action: NoticeCard.Action(title: OnboardingStrings.enable, command: .enableOpenAtLogin)
        )
    }

    static var enableDirectPaste: NoticeCard {
        NoticeCard(
            id: "enableDirectPaste",
            symbol: "return",
            title: OnboardingStrings.directPasteNoticeTitle,
            description: OnboardingStrings.directPasteNoticeDescription,
            action: NoticeCard.Action(title: OnboardingStrings.enable, command: .enableDirectPaste)
        )
    }

    /// Capture finds pasteboard access short of "always allow": nothing copied is saved until
    /// it is.
    static var pasteboardAccess: NoticeCard {
        NoticeCard(
            id: "pasteboardAccess",
            symbol: "clipboard",
            title: OnboardingStrings.pasteboardAccessNoticeTitle,
            description: OnboardingStrings.pasteboardAccessNoticeDescription,
            action: NoticeCard.Action(title: OnboardingStrings.allow, command: .allowPasteboardAccess)
        )
    }

    static let otherClipboardManagersID = "otherClipboardManagers"

    /// Other clipboard managers are open: two apps keep what is copied, and a shortcut they
    /// share reaches only one. Informative; nil when there are none.
    static func otherClipboardManagers(named names: [String]) -> NoticeCard? {
        guard !names.isEmpty else { return nil }
        return NoticeCard(
            id: otherClipboardManagersID,
            symbol: "square.on.square",
            title: OnboardingStrings.otherClipboardManagersNoticeTitle,
            description: OnboardingStrings.otherClipboardManagersNoticeDescription(ListFormatter.localizedString(byJoining: names)),
            action: NoticeCard.Action(title: OnboardingStrings.gotIt, command: .acknowledgeOtherClipboardManagers)
        )
    }

    /// The store keeps failing to save: what is copied is lost, most likely because the disk
    /// is full. The button opens System Settings › General › Storage.
    static var storeWriteFailure: NoticeCard {
        NoticeCard(
            id: "storeWriteFailure",
            symbol: "externaldrive.badge.exclamationmark",
            title: OnboardingStrings.storeWriteFailureNoticeTitle,
            description: OnboardingStrings.storeWriteFailureNoticeDescription,
            action: NoticeCard.Action(title: OnboardingStrings.storage, command: .openStorageSettings)
        )
    }

    static let shortcutsTakenID = "shortcutsTaken"

    /// Shortcuts of the user's that something else answers to: they may not reach Pasto. The
    /// button leads to Settings › Shortcuts. Nil when there are none.
    ///
    /// - Parameter shortcuts: The shortcuts, as shown ("⇧⌘V").
    static func shortcutsTaken(_ shortcuts: [String]) -> NoticeCard? {
        guard !shortcuts.isEmpty else { return nil }
        return NoticeCard(
            id: shortcutsTakenID,
            symbol: "keyboard",
            title: OnboardingStrings.shortcutsTakenNoticeTitle,
            description: OnboardingStrings.shortcutsTakenNoticeDescription(ListFormatter.localizedString(byJoining: shortcuts)),
            action: NoticeCard.Action(title: OnboardingStrings.change, command: .openShortcutSettings)
        )
    }

    /// What the end of onboarding leaves on show, in order: a card for each thing still off,
    /// then one naming the other clipboard managers that are open.
    static func cardsAfterOnboarding(
        isLoginItemEnabled: Bool,
        isDirectPasteEnabled: Bool,
        otherClipboardManagers: [String] = []
    ) -> [NoticeCard] {
        var cards: [NoticeCard] = []
        if !isLoginItemEnabled { cards.append(openAtLogin) }
        if !isDirectPasteEnabled { cards.append(enableDirectPaste) }
        if let card = Self.otherClipboardManagers(named: otherClipboardManagers) { cards.append(card) }
        return cards
    }
}
