import AppKit
import Observation

/// The state behind the screens that ask for Accessibility or pasteboard access: what the
/// button does, watching for the grant, and keeping a modal window out of the system's way. The
/// welcome's permission steps use it too, with their own look.
@MainActor
@Observable
public final class AccessRequestModel {
    public enum Permission: Sendable {
        case accessibility
        case pasteboard
    }

    enum Configuration {
        /// In a modal window of its own, cancelled with the close button.
        case regular
        /// As a step of onboarding, which can be skipped.
        case onboarding
    }

    public let permission: Permission
    let configuration: Configuration
    /// The system only shows its alert once; afterwards the button leads to System Settings.
    public private(set) var opensSystemSettings: Bool
    public private(set) var isAccessEnabled = false
    /// For pasteboard access, the choice System Settings holds now, refreshed with the grant.
    public private(set) var pasteboardAccess: PasteboardAccess
    /// The modal window showing the screen, if it is not part of onboarding.
    @ObservationIgnored weak var window: PermissionWindowController?

    private let onFinish: (PermissionOutcome) -> Void
    @ObservationIgnored private var observations: [Task<Void, Never>] = []
    @ObservationIgnored private var hasSeenState = false

    init(permission: Permission, configuration: Configuration, onFinish: @escaping (PermissionOutcome) -> Void) {
        self.permission = permission
        self.configuration = configuration
        self.onFinish = onFinish
        pasteboardAccess = permission == .pasteboard ? PasteboardAccess.current : .undetermined
        switch permission {
        case .accessibility: opensSystemSettings = AccessibilityAccess.hasSystemDecision
        case .pasteboard: opensSystemSettings = true
        }
    }

    /// A permission as a step of the welcome: skipping it, or going on once it is granted,
    /// calls `onFinish`. Granted while the step is on show, it goes on by itself a moment later.
    public static func onboardingStep(_ permission: Permission, onFinish: @escaping () -> Void) -> AccessRequestModel {
        AccessRequestModel(permission: permission, configuration: .onboarding) { _ in onFinish() }
    }

    isolated deinit {
        stopObserving()
    }

    public func startObserving() {
        guard observations.isEmpty else { return }
        if permission == .pasteboard {
            PasteboardAccess.provokeSystemAlertIfUndetermined()
        }
        observations = [
            Task { [weak self] in
                for await bundleIdentifier in FrontmostApplication.bundleIdentifiers() {
                    self?.frontmostApplicationChanged(to: bundleIdentifier)
                }
            },
            Task { [weak self, states = accessStates] in
                for await isGranted in states {
                    guard let self else { return }
                    stateChanged(to: isGranted)
                    if isAccessEnabled { return }
                }
            },
            // What System Settings holds for the pasteboard, which the step shows, changes without
            // the grant changing (Ask, Deny).
            Task { [weak self, permission] in
                guard permission == .pasteboard else { return }
                for await access in PasteboardAccess.choices() {
                    guard let self else { return }
                    if pasteboardAccess != access { pasteboardAccess = access }
                }
            },
            // Coming back from System Settings shows the change at once, not at the next poll.
            Task { [weak self] in
                let activations = NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification).map { _ in }
                for await _ in activations {
                    guard let self, !isAccessEnabled else { return }
                    if permission == .pasteboard { pasteboardAccess = PasteboardAccess.current }
                    stateChanged(to: currentState)
                }
            },
        ]
    }

    public func stopObserving() {
        observations.forEach { $0.cancel() }
        observations = []
    }

    /// What the main button says: ask the system, or, once it has asked, go to System Settings.
    public var primaryActionTitle: String {
        opensSystemSettings ? PermissionStrings.openSystemSettings : PermissionStrings.allowAccess
    }

    public func performPrimaryAction() {
        switch permission {
        case .accessibility where !AccessibilityAccess.hasSystemDecision:
            // The system's alert belongs to another process: Pasto steps back so it shows in front.
            NSApp.deactivate()
            AccessibilityAccess.requestShowingSystemPrompt()
            window?.level = .normal
            opensSystemSettings = true
        case .accessibility:
            SystemSettingsPane.accessibility.open()
            SystemSettingsPane.activate()
        case .pasteboard:
            SystemSettingsPane.pasteboard.open()
        }
    }

    /// Goes on without the permission, or, once it is granted, goes on.
    public func skip() {
        stopObserving()
        onFinish(.cancel)
    }

    private var currentState: Bool {
        switch permission {
        case .accessibility: AccessibilityAccess.isGranted
        case .pasteboard: PasteboardAccess.isAlwaysAllowed
        }
    }

    private var accessStates: AsyncStream<Bool> {
        switch permission {
        case .accessibility: AccessibilityAccess.states()
        case .pasteboard: PasteboardAccess.states()
        }
    }

    private func stateChanged(to isGranted: Bool) {
        let isFirst = !hasSeenState
        hasSeenState = true
        guard isGranted, !isAccessEnabled else { return }
        if permission == .pasteboard { pasteboardAccess = .alwaysAllowed }
        if isFirst, configuration == .onboarding {
            // Already there when the step came on show: nothing to wait for, and the step waits
            // for the user to go on instead of going on by itself.
            stopObserving()
            isAccessEnabled = true
        } else {
            accessWasGranted()
        }
    }

    /// Keeps the modal window out of the way of System Settings and, for Accessibility, of the
    /// system's prompt. In onboarding there is no such window.
    private func frontmostApplicationChanged(to bundleIdentifier: String?) {
        guard !isAccessEnabled else { return }
        window?.level = PermissionWindowLevel.level(
            frontmostBundleIdentifier: bundleIdentifier,
            includesAccessibilityPrompts: permission == .accessibility
        )
    }

    /// Stops watching, comes back to the front, confirms for a moment and finishes. Once the
    /// confirmation is on screen nothing cancels it.
    private func accessWasGranted() {
        stopObserving()
        NSApp.activate(ignoringOtherApps: true)
        isAccessEnabled = true
        // The confirmation is only on screen for a moment: VoiceOver says it at once.
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: PermissionStrings.accessGranted, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        if configuration == .regular {
            window?.level = .modalPanel
            window?.removeCloseButton()
        }
        Task { [onFinish] in
            try? await Task.sleep(for: PermissionMetrics.grantedConfirmationDuration)
            onFinish(.success)
        }
    }
}

extension AccessRequestModel.Permission {
    /// The title of the screen that asks for it.
    public var title: String {
        switch self {
        case .accessibility: PermissionStrings.accessibilityTitle
        case .pasteboard: PermissionStrings.pasteboardTitle
        }
    }

    /// What the screen that asks for it says.
    public var subtitle: String {
        switch self {
        case .accessibility: PermissionStrings.accessibilitySubtitle
        case .pasteboard: PermissionStrings.pasteboardSubtitle
        }
    }
}
