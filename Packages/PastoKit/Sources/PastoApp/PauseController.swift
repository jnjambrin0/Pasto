import AppKit
import PastoCore
import PastoUI
import SwiftUI

/// Pausing capture: the pasteboard is simply not watched while paused, so what is copied
/// meanwhile never reaches the history. A pause is not remembered across launches.
final class PauseController {
    /// The durations offered in the menu, in seconds: 15 m, 30 m, 1 h, 3 h, 8 h.
    static let durations: [TimeInterval] = [900, 1_800, 3_600, 10_800, 28_800]

    private let historyManager: HistoryManager
    private var timer: Timer?
    /// The last order sent to the history manager; the next one waits for it, so that a pause
    /// followed at once by a resume cannot arrive the other way round.
    private var pendingOrder: Task<Void, Never>?

    private(set) var isPaused = false
    /// When a timed pause ends; nil while not paused or paused indefinitely.
    private(set) var resumeDate: Date?
    /// Called after pausing, resuming, or giving a pause that is already on another end.
    var onChange: (() -> Void)?

    init(historyManager: HistoryManager) {
        self.historyManager = historyManager
    }

    /// ⌘T. Pausing gives the previous application its focus back, which closes the panel.
    func toggle() {
        if isPaused {
            resume()
        } else {
            NSApp.deactivate()
            pause(until: nil)
        }
    }

    func pause(for duration: TimeInterval) {
        pause(until: Date(timeIntervalSinceNow: duration))
    }

    /// Pauses, or re-schedules a pause that is already on.
    func pause(until date: Date?) {
        timer?.invalidate()
        timer = nil
        resumeDate = date
        OSD.show(
            symbol: "pause",
            title: AppStrings.paused,
            subtitle: date.map { Text(AppStrings.until(Self.timeFormatter.string(from: $0))) }
        )
        setMonitoringPaused(true)
        if let date {
            timer = Timer.scheduledTimer(withTimeInterval: max(date.timeIntervalSinceNow, 0), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            }
        }
    }

    func resume() {
        timer?.invalidate()
        timer = nil
        OSD.show(symbol: "arrow.clockwise", title: AppStrings.resumed)
        resumeDate = nil
        setMonitoringPaused(false)
    }

    /// Title of the pause entry in the app menu.
    var menuTitle: String {
        if let resumeDate { return AppStrings.until(Self.timeFormatter.string(from: resumeDate)) }
        return isPaused ? AppStrings.pausedShort : AppStrings.pausePasto
    }

    private func setMonitoringPaused(_ paused: Bool) {
        isPaused = paused
        onChange?()
        pendingOrder = Task { [historyManager, pendingOrder] in
            await pendingOrder?.value
            await historyManager.setPaused(paused)
        }
    }

    /// Always a 24-hour clock, whatever the locale.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
