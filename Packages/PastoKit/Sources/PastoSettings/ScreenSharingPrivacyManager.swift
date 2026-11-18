import AppKit
import PastoCore
import PastoFoundation

/// Keeps Pasto's windows in or out of screenshots, recordings and shared screens, as Settings ›
/// Privacy › "Show during screen sharing" says.
///
/// The setting reaches every window when the manager starts and whenever it changes, and each
/// window again as it becomes key, which covers the windows made since. A window that never
/// becomes key keeps the system's default until the setting next changes.
public final class ScreenSharingPrivacyManager {
    private let config: ConfigStore
    private var settingObservation: Task<Void, Never>?
    private var keyWindowObserver: (any NSObjectProtocol)?

    public init(config: ConfigStore) {
        self.config = config
    }

    isolated deinit {
        settingObservation?.cancel()
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
    }

    /// Call once, as the app starts.
    public func start() {
        guard settingObservation == nil else { return }
        applyToEveryWindow(config.value(for: .isScreenSharingContentVisible))
        settingObservation = Task { [weak self, config] in
            for await isVisible in config.values(for: .isScreenSharingContentVisible) {
                self?.applyToEveryWindow(isVisible)
            }
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [config] _ in
            MainActor.assumeIsolated {
                NSApp.keyWindow?.sharingType = Self.sharingType(isVisible: config.value(for: .isScreenSharingContentVisible))
            }
        }
    }

    private func applyToEveryWindow(_ isVisible: Bool) {
        let sharingType = Self.sharingType(isVisible: isVisible)
        for window in NSApp.windows {
            window.sharingType = sharingType
        }
    }

    /// Visible means readable by captures, never writable by them.
    private static func sharingType(isVisible: Bool) -> NSWindow.SharingType {
        isVisible ? .readOnly : .none
    }
}
