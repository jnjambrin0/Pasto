import Foundation

/// Where the launch of Pasto is, from the process coming up to the app being ready to use. Each
/// phase is logged as it starts and kept in the launch record, so that a launch that never got
/// to `ready` says where it stopped.
public nonisolated enum LaunchPhase: String, Codable, Sendable, CaseIterable {
    /// The process is up; nothing has been done yet.
    case started
    /// Looking for another copy of Pasto that is already running, and settling with it.
    case checkingOtherCopies
    /// The copy runs from somewhere it should be moved from: the user is asked, and the copy
    /// may be moved.
    case relocating
    /// The store is opened — and migrated first, when an older version wrote it.
    case openingStore
    /// The store could not be opened: the user is asked what to do.
    case storeFailure
    /// The app is put together: the login-item wait, the menus, the updater, the shortcuts,
    /// the menu bar icon and capture.
    case startingApp
    /// The welcome window is up, on a first launch: the launch waits for the user.
    case welcome
    /// After the welcome: the menu bar icon, the shortcuts and capture.
    case connecting
    /// The menu bar icon and the shortcuts are in place and capture runs.
    case ready

    /// Whether the launch is waiting for the user — an alert or the welcome window — rather
    /// than for the app. No time limit applies then.
    public var isWaitingForUser: Bool {
        switch self {
        case .relocating, .storeFailure, .welcome: true
        default: false
        }
    }

    /// How long the launch may stay in this phase before it counts as stalled, or nil when no
    /// limit applies: the phases that wait for the user, and `ready`. Each limit is many times
    /// what the phase takes on a slow Mac.
    public var stallLimit: TimeInterval? {
        switch self {
        case .started: 10
        // A copy that is quitting gets 3 s, a stuck one 3 + 2 s more, opening another 5 s.
        case .checkingOtherCopies: 20
        // A migration rewrites the tables of the whole store.
        case .openingStore: 60
        // Includes the 5 s a login item waits for the session.
        case .startingApp: 30
        case .connecting: 20
        case .relocating, .storeFailure, .welcome, .ready: nil
        }
    }
}
