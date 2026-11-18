import AppKit
import Foundation
@_spi(Benchmarks) import PastoCore
import PastoFoundation

/// The general pasteboard's change count and nothing else: polling costs what it costs in the
/// app, while the contents are never read (`items()` says the pasteboard cannot be read).
final class ChangeCountOnlySource: PasteboardSource, @unchecked Sendable {
    var changeCount: Int { NSPasteboard.general.changeCount }
    var allowsProgrammaticReads: Bool { false }
    func items() -> [any PasteboardSourceItem]? { nil }
    func string(forType type: String) -> String? { nil }
    func write(_ items: [PasteboardItemSnapshot]) -> Int { changeCount }
}

enum IdleScenario {
    /// CPU time and wakeups of the process over `seconds` at rest, with the pasteboard watched
    /// (`leewayMilliseconds` of tolerance on the poll timer) or not watched at all.
    @MainActor
    static func run(seconds: Int, monitoring: Bool, leewayMilliseconds: Int?) async throws {
        let suiteName = "jnjambrino.Pasto.CaptureBench.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        var configuration = SystemPasteboard.Configuration.standard
        if let leewayMilliseconds {
            configuration.pollLeeway = .milliseconds(leewayMilliseconds)
        }
        let pasteboard = SystemPasteboard(
            source: ChangeCountOnlySource(),
            configuration: configuration,
            config: ConfigStore(defaults: UserDefaults(suiteName: suiteName)!),
            applications: BenchApplication()
        )
        if monitoring {
            pasteboard.startMonitoring()
        }
        // Let start-up settle before counting.
        try await Task.sleep(for: .seconds(2))
        let cpuBefore = ProcessMetrics.cpuTime()
        let wakeupsBefore = ProcessMetrics.wakeups()
        try await Task.sleep(for: .seconds(seconds))
        let cpu = ProcessMetrics.cpuTime() - cpuBefore
        let wakeups = ProcessMetrics.wakeups()
        pasteboard.stopMonitoring()

        ResultLine(scenario: "idle", values: [
            "seconds": Double(seconds),
            "cpu_percent": cpu / Double(seconds) * 100,
            "interrupt_wakeups_per_s": Double(wakeups.interrupt - wakeupsBefore.interrupt) / Double(seconds),
            "idle_wakeups_per_s": Double(wakeups.idle - wakeupsBefore.idle) / Double(seconds),
            "leeway_ms": Double(leewayMilliseconds ?? 25),
        ], notes: ["monitoring": "\(monitoring)"]).print()
    }
}
