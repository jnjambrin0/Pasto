import Foundation
import ServiceManagement

/// "Open at login": Pasto registered with the system as a login item. The system holds the
/// state; there is no setting for it.
public struct LoginItemService: Sendable {
    /// What the system says of the registration.
    public enum Status: Sendable, Equatable {
        case enabled
        /// Registered, but the user turned it off in System Settings › General › Login Items,
        /// or has yet to approve it there: Pasto will not open at login until they do.
        case requiresApproval
        case notRegistered
        /// The system cannot find the app to register: it runs from somewhere it does not
        /// accept, such as a disk image.
        case notFound
    }

    private static let didChange = Notification.Name("PastoLoginItemDidChange")

    public init() {}

    public var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    public var isEnabled: Bool {
        status == .enabled
    }

    public func setEnabled(_ isEnabled: Bool) throws {
        let service = SMAppService.mainApp
        if isEnabled {
            // Registering again refreshes a registration left by a previous copy of the app.
            if service.status == .enabled {
                try? service.unregister()
            }
            try service.register()
        } else {
            try service.unregister()
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Opens System Settings › General › Login Items, where the user approves or allows what
    /// macOS blocks.
    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The state after every change made through this service. The system has no notification
    /// of its own for it.
    public func changes() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            // The token only ever goes back to `NotificationCenter`, which is thread-safe.
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: Self.didChange, object: nil, queue: nil
            ) { _ in continuation.yield(isEnabled) }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        }
    }
}
