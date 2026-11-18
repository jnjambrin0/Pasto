import Foundation
import PastoFoundation

/// A request for screen recording access that Pasto has made and not yet seen granted.
///
/// macOS lets a process capture the screen only once it has started again after the grant, so
/// when the user turns Pasto on in System Settings, System Settings offers "Quit & Reopen" and
/// quits Pasto. The request is saved so that the process that comes back knows the user was in
/// the middle of granting it, and from where, and can take them back there.
public struct ScreenRecordingRequest: Codable, Equatable, Sendable {
    /// Where the user asked for the access, which is where Pasto takes them back to.
    public enum Origin: String, Codable, Sendable {
        /// The suggestions step of a first launch's welcome.
        case onboarding
        /// The suggestions step of the welcome shown again from Help › Getting Started.
        case gettingStarted
        /// The suggestions strip of the panel.
        case panel
        /// Settings › Intelligence.
        case settings
    }

    /// How long a request is worth honouring: finding Pasto in System Settings and turning it on
    /// takes minutes, not hours.
    public static let lifetime: TimeInterval = 15 * 60
    /// A clock set back by this much still counts the request as made now.
    static let clockTolerance: TimeInterval = 60

    public let origin: Origin
    public let date: Date
    /// Set as Pasto quits because System Settings asked it to while the request was pending: the
    /// next launch is the "reopen".
    public var relaunchDate: Date?

    public init(origin: Origin, date: Date, relaunchDate: Date? = nil) {
        self.origin = origin
        self.date = date
        self.relaunchDate = relaunchDate
    }

    public func isPending(at now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age > -Self.clockTolerance && age < Self.lifetime
    }

    /// Whether Pasto, quitting at `now` because of `quit`, has to open itself again: only when
    /// System Settings asks while the request is pending, never when the user quits Pasto or
    /// logs out. A sender that can no longer be told counts as System Settings, the only process
    /// that quits Pasto while it waits for a grant.
    public func callsForRelaunch(after quit: QuitRequest, at now: Date) -> Bool {
        guard isPending(at: now), case .appleEvent(let sender, let hasReason) = quit, !hasReason else { return false }
        switch sender {
        case .systemSettings, .unknown: return true
        case .other: return false
        }
    }

    /// What a launch at `now` does with the request.
    ///
    /// - Parameter isGranted: Whether this process can capture the screen.
    public func resumption(at now: Date, isGranted: Bool) -> Resumption {
        guard isPending(at: now) else { return .discard }
        if isGranted {
            // Granted since it was asked for: this is the reopen, whoever reopened Pasto.
            return .resume(origin, keepsRequest: false)
        }
        if relaunchDate != nil {
            // System Settings quit Pasto for it, yet it is not granted: the user still has to
            // finish, so they are taken back without forgetting the request.
            return .resume(origin, keepsRequest: true)
        }
        // An ordinary launch while the user is still deciding.
        return .keep
    }

    public enum Resumption: Equatable, Sendable {
        /// Too old: forget it.
        case discard
        /// Leave it as it is and launch as usual.
        case keep
        /// Take the user back to `origin`; forget the request unless `keepsRequest`.
        case resume(Origin, keepsRequest: Bool)
    }
}

extension ConfigKey where Value == JSONConfigValue<ScreenRecordingRequest?> {
    /// The screen recording request waiting to be seen granted, if any.
    public static var screenRecordingRequest: ConfigKey<JSONConfigValue<ScreenRecordingRequest?>> {
        ConfigKey("pendingScreenRecordingRequest", default: JSONConfigValue(nil))
    }
}

extension ConfigStore {
    /// The pending request, whether or not it is still worth honouring.
    public var screenRecordingRequest: ScreenRecordingRequest? {
        value(for: .screenRecordingRequest).value
    }

    /// Remembers that the user asked for screen recording access from `origin`, now.
    public func recordScreenRecordingRequest(from origin: ScreenRecordingRequest.Origin, at date: Date = Date()) {
        set(JSONConfigValue(ScreenRecordingRequest(origin: origin, date: date)), for: .screenRecordingRequest)
    }

    public func clearScreenRecordingRequest() {
        reset(.screenRecordingRequest)
    }
}
