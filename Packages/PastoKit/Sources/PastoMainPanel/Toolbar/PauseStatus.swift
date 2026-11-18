import Foundation

/// Whether clipboard capture is paused, as the toolbar's indicator shows it.
public nonisolated enum PauseStatus: Equatable, Sendable {
    case running
    /// Paused until that moment, or until the user resumes when there is none.
    case paused(until: Date?)

    /// What the indicator says; nil while capture runs, when there is no indicator.
    @MainActor
    func indicatorText(timeZone: TimeZone = .current) -> String? {
        switch self {
        case .running:
            return nil
        case .paused(until: nil):
            return PanelStrings.paused
        case .paused(until: let date?):
            // A 24-hour clock whatever the user's settings.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            return PanelStrings.pausedUntil(formatter.string(from: date))
        }
    }
}
