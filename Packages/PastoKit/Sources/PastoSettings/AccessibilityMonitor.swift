import Observation
import PastoPermissions

/// Whether Pasto has Accessibility access, kept current while Settings is open.
@Observable
final class AccessibilityMonitor {
    private(set) var isGranted = AccessibilityAccess.isGranted
    @ObservationIgnored private var observation: Task<Void, Never>?

    init() {
        observation = Task { [weak self] in
            for await isGranted in AccessibilityAccess.states() {
                guard let self else { return }
                self.isGranted = isGranted
            }
        }
    }

    isolated deinit {
        observation?.cancel()
    }
}
