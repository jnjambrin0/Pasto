import AppKit
import PastoCore
import PastoFoundation

/// Pasto's menu bar icon: a click toggles the panel, a right click (or Control-click) shows the
/// app menu.
public final class StatusItem: NSObject {
    private enum Metrics {
        /// The whole capture pulse, dimming and back: a third of a second.
        static let captureAnimationDuration: TimeInterval = 16.0 / 48.0
        static let captureAnimationDimmedAlpha: CGFloat = 0.35
    }

    private let statusItem: NSStatusItem
    private let onClick: () -> Void
    private let menuProvider: () -> NSMenu
    private var visibilityObservation: Task<Void, Never>?

    public var isPaused = false {
        didSet {
            if isPaused != oldValue { updateImage() }
        }
    }

    /// Why capture saves nothing (pasteboard access is missing), or nil while it works. The
    /// icon then shows dimmed and says why on hover: the reminder that stays once the window
    /// that asks for access has been shown.
    public var captureBlockedReason: String? {
        didSet {
            if captureBlockedReason != oldValue { updateImage() }
        }
    }

    /// What VoiceOver adds to the icon's name while capture is paused ("Paused"). This module has
    /// no strings of its own: the app gives it in the user's language. Nil, nothing is added.
    public var pausedAccessibilityValue: String? {
        didSet { updateAccessibility() }
    }

    /// The icon is a picture: VoiceOver needs a name for it, the app's.
    private static var accessibilityLabel: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Pasto"
    }

    /// - Parameters:
    ///   - onClick: A plain click: toggle the panel.
    ///   - menuProvider: Builds the app menu, afresh for every right click.
    public init(config: ConfigStore, onClick: @escaping () -> Void, menuProvider: @escaping () -> NSMenu) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onClick = onClick
        self.menuProvider = menuProvider
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemAction)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateImage()

        // The setting applies at once, in both directions.
        visibilityObservation = Task { [weak self] in
            for await isEnabled in config.values(for: .isStatusItemEnabled) {
                self?.statusItem.isVisible = isEnabled
            }
        }
    }

    isolated deinit {
        visibilityObservation?.cancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Something new reached the front of the history: a brief pulse of the icon.
    public func animateCapture() {
        guard let button = statusItem.button, !isPaused else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.captureAnimationDuration / 2
            button.animator().alphaValue = Metrics.captureAnimationDimmedAlpha
        } completionHandler: {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Metrics.captureAnimationDuration / 2
                    button.animator().alphaValue = 1
                }
            }
        }
    }

    private func updateImage() {
        let image = isPaused
            ? NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Pasto")
            : NSImage(named: "StatusItemIcon")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = captureBlockedReason != nil
        statusItem.button?.toolTip = captureBlockedReason
        updateAccessibility()
    }

    /// The name, and what is wrong or paused: why capture is blocked comes first, since it is
    /// what the dimmed icon is saying.
    private func updateAccessibility() {
        statusItem.button?.setAccessibilityLabel(Self.accessibilityLabel)
        statusItem.button?.setAccessibilityValue(captureBlockedReason ?? (isPaused ? pausedAccessibilityValue : nil))
    }

    @objc private func statusItemAction() {
        guard let event = NSApp.currentEvent else { return }
        let isMenuClick = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        guard isMenuClick else {
            onClick()
            return
        }
        // The menu is attached only for the duration of this click, so that a plain click keeps
        // reaching the action instead of opening it.
        statusItem.menu = menuProvider()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
