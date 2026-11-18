import AppKit
import Observation
import PastoFoundation

/// Screen recording access for suggestions, as the window and the welcome's suggestions step
/// show it: whether it is granted, live, what the button does, and the capture check that gets
/// macOS's own confirmation out of the way.
@MainActor
@Observable
public final class ScreenRecordingAccessModel {
    public enum Confirmation: Equatable, Sendable {
        /// The check has not gone through in this installation yet.
        case pending
        case running
        case confirmed
        /// macOS refused the capture: the user did not allow it.
        case failed
    }

    /// Whether this process can capture the screen. A grant only reaches a process started
    /// after it: until System Settings has quit and reopened Pasto, it stays false.
    public private(set) var isGranted: Bool
    /// The system shows its alert only the first time; afterwards the button leads to System
    /// Settings.
    public private(set) var opensSystemSettings: Bool
    public private(set) var confirmation: Confirmation

    private let config: ConfigStore
    private let origin: ScreenRecordingRequest.Origin
    @ObservationIgnored private var observation: Task<Void, Never>?

    /// - Parameter origin: Where the user is asking from, which is where they are taken back to
    ///   once System Settings has reopened Pasto.
    public init(config: ConfigStore, origin: ScreenRecordingRequest.Origin) {
        self.config = config
        self.origin = origin
        isGranted = ScreenRecordingAccess.isGranted
        opensSystemSettings = config.value(for: .isScreenRecordingAccessRequested)
        confirmation = ScreenCaptureCheck.lastConfirmation(in: config) == nil ? .pending : .confirmed
    }

    isolated deinit {
        observation?.cancel()
    }

    /// Follows the access, looked at again whenever an application — Pasto included — becomes
    /// active: the user grants it in System Settings and comes back.
    public func startObserving() {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            for await isGranted in ScreenRecordingAccess.states() {
                self?.isGranted = isGranted
            }
        }
    }

    public func stopObserving() {
        observation?.cancel()
        observation = nil
    }

    /// The first time, the system shows its own alert. It never does again, so from then on the
    /// button also opens System Settings. Either way the request is remembered: System Settings
    /// will quit Pasto to apply the grant, and the next launch brings the user back here.
    public func requestAccess() {
        config.recordScreenRecordingRequest(from: origin)
        let wasRequested = config.value(for: .isScreenRecordingAccessRequested)
        config.set(true, for: .isScreenRecordingAccessRequested)
        opensSystemSettings = true
        ScreenRecordingAccess.request()
        if wasRequested {
            SystemSettingsPane.screenRecording.open()
        }
    }

    /// Captures once, so that macOS asks its confirmation now.
    public func confirm() async {
        guard confirmation != .running else { return }
        confirmation = .running
        switch await ScreenCaptureCheck.run(config: config) {
        case .confirmed:
            confirmation = .confirmed
            config.clearScreenRecordingRequest()
        case .notGranted:
            isGranted = false
            confirmation = .pending
        case .failed:
            confirmation = .failed
        }
    }
}
