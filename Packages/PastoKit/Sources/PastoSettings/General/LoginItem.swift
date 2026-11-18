import AppKit
import Observation
import os
import PastoCore
import PastoFoundation

/// The "Open at login" switch of the General pane. It follows the changes made elsewhere too,
/// such as from a notice card, and says when macOS does not let Pasto open at login.
@Observable
final class LoginItem {
    private(set) var isEnabled: Bool
    /// The switch is on but macOS will not open Pasto at login: the user turned it off in
    /// System Settings › General › Login Items, has yet to approve it there, or the system
    /// refused the registration. The pane then offers to open those settings.
    private(set) var isBlockedBySystem: Bool
    private let service = LoginItemService()
    private let log = Log.logger(.app)
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init() {
        (isEnabled, isBlockedBySystem) = Self.state(of: service.status)
        observation = Task { [weak self, service] in
            for await _ in service.changes() {
                guard let self else { return }
                (isEnabled, isBlockedBySystem) = Self.state(of: service.status)
            }
        }
        // Coming back from System Settings, where the user may have approved it.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBlock() }
        }
    }

    isolated deinit {
        observation?.cancel()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    /// The switch shows what was asked for even if the system then refuses; what the system made
    /// of it shows under the switch.
    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        do {
            try service.setEnabled(isEnabled)
        } catch {
            log.error("Could not \(isEnabled ? "register" : "unregister", privacy: .public) the login item: \(error)")
        }
        refreshBlock()
    }

    func openSystemSettings() {
        LoginItemService.openSystemSettings()
    }

    /// After a request, or on coming back: a switch that is on and a system that does not
    /// open Pasto at login disagree.
    private func refreshBlock() {
        isBlockedBySystem = isEnabled && service.status != .enabled
    }

    /// Registered but waiting for approval is what the user asked for: the switch shows on,
    /// with the block under it.
    private static func state(of status: LoginItemService.Status) -> (isEnabled: Bool, isBlockedBySystem: Bool) {
        (status == .enabled || status == .requiresApproval, status == .requiresApproval)
    }
}
