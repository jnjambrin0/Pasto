import AppKit
import Observation

/// Listens for the key combination that becomes a shortcut: a key with ⌘, ⌃ or ⌥ — or a function
/// key on its own — is recorded unless something else has it, Delete clears, Escape leaves things
/// as they were, and so do ⌘W, ⌘Q, Tab, ⇧Tab and the window losing key status.
@MainActor
@Observable
public final class ShortcutRecorder {
    public enum Ending: Equatable, Sendable {
        case recorded(Shortcut)
        case cleared
        /// The field keeps what it had: the user cancelled, or the combination is in use.
        case cancelled
    }

    public private(set) var isRecording = false
    /// The modifiers held down while recording, shown as feedback.
    public private(set) var heldModifiers: NSEvent.ModifierFlags = []
    /// Why the last combination could not be recorded, for the owner to tell the user. It stays
    /// until the owner sets it back to nil.
    public var conflict: ShortcutConflict?

    private let hotKeys: HotKeyCenter
    @ObservationIgnored private var otherShortcuts: [NamedShortcut] = []
    @ObservationIgnored private var onEnd: ((Ending) -> Void)?
    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var resignKeyObserver: (any NSObjectProtocol)?

    /// - Parameter hotKeys: Paused while recording: Pasto's own hot keys would swallow their
    ///   combinations before the recorder could see them.
    public init(hotKeys: HotKeyCenter) {
        self.hotKeys = hotKeys
    }

    isolated deinit {
        stopListening()
    }

    /// Has VoiceOver say `text` now: that recording started, or what it ended with — the field
    /// changes under the cursor without taking the focus. The owner says it, in its words.
    public static func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    /// Starts listening, ending any recording already under way.
    ///
    /// - Parameters:
    ///   - otherShortcuts: Pasto's shortcuts other than the one being recorded, which cannot be
    ///     recorded again.
    ///   - onEnd: Called exactly once, however the recording ends.
    public func start(otherShortcuts: [NamedShortcut], onEnd: @escaping (Ending) -> Void) {
        cancel()
        self.otherShortcuts = otherShortcuts
        self.onEnd = onEnd
        hotKeys.pause()
        isRecording = true
        heldModifiers = []
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    public func cancel() {
        end(.cancelled)
    }

    private func end(_ ending: Ending) {
        guard isRecording else { return }
        stopListening()
        let onEnd = onEnd
        self.onEnd = nil
        onEnd?(ending)
    }

    private func stopListening() {
        guard isRecording else { return }
        isRecording = false
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        eventMonitor = nil
        resignKeyObserver = nil
        hotKeys.resume()
    }

    /// Returns the event when it goes on to the application, nil when the recording used it up.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else {
            heldModifiers = Shortcut(keyCode: 0, modifiers: event.modifierFlags).modifiers
            return nil
        }
        let outcome = ShortcutRecording.outcome(
            keyCode: Int(event.keyCode),
            modifiers: event.modifierFlags,
            otherShortcuts: otherShortcuts
        ) { shortcut in
            ShortcutValidator.current().conflict(for: shortcut, key: ShortcutValidator.key(forKeyCode: shortcut.keyCode))
        }
        switch outcome {
        case .record(let shortcut):
            end(.recorded(shortcut))
        case .clear:
            end(.cleared)
        case .cancel:
            end(.cancelled)
        case .cancelAndPassOn:
            end(.cancelled)
            return event
        case .reject:
            NSSound.beep()
            return event
        case .conflict(let conflict):
            end(.cancelled)
            self.conflict = conflict
        }
        return nil
    }
}
