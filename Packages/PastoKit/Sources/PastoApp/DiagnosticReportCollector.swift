import Foundation
import MetricKit
import os
import PastoFoundation

/// Keeps the crash, hang and exception reports macOS gathers about Pasto, on this Mac only.
/// MetricKit hands them over the next time Pasto runs; each payload is saved as it comes, in
/// `DiagnosticReportStore`'s folder. Nothing is sent anywhere: "Report a Problem…" offers to show
/// the files so the user can attach them.
nonisolated final class DiagnosticReportCollector: NSObject, MXMetricManagerSubscriber {
    private let store: DiagnosticReportStore

    init(store: DiagnosticReportStore = DiagnosticReportStore()) {
        self.store = store
    }

    func start() {
        MXMetricManager.shared.add(self)
        Task.detached(priority: .utility) { [store] in store.prune() }
    }

    /// Called by MetricKit on a queue of its own.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let log = Log.logger(.app)
        for payload in payloads {
            do {
                let url = try store.save(payload.jsonRepresentation(), as: .report, at: payload.timeStampEnd)
                log.notice("Saved a diagnostic report: \(url.lastPathComponent, privacy: .public)")
            } catch {
                log.error("Could not save a diagnostic report: \(error)")
            }
        }
        store.prune()
    }
}
