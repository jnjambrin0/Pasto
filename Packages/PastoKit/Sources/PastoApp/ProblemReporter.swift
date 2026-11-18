import AppKit
import os
import OSLog
import PastoFoundation

/// "Report a Problem…" in the Help menu. The user writes the report, by email or on the website's
/// contact page, with the versions of Pasto and macOS already filled in. Pasto sends nothing: it
/// can show its diagnostic files in Finder — the crash and hang reports MetricKit handed over and
/// the log of this session, which it saves then — for the user to attach.
final class ProblemReporter {
    private let store: DiagnosticReportStore
    private let log = Log.logger(.app)

    init(store: DiagnosticReportStore = DiagnosticReportStore()) {
        self.store = store
    }

    func run() {
        let alert = NSAlert()
        alert.messageText = AppStrings.reportProblemTitle
        alert.informativeText = AppStrings.reportProblemMessage
        // The first button answers Return.
        alert.addButton(withTitle: AppStrings.reportProblemEmail)
        alert.addButton(withTitle: AppStrings.reportProblemContactPage)
        alert.addButton(withTitle: AppStrings.cancel)
        let showFiles = NSButton(checkboxWithTitle: AppStrings.reportProblemShowFiles, target: nil, action: nil)
        showFiles.state = .on
        alert.accessoryView = showFiles
        NSApp.activate(ignoringOtherApps: true)

        let details = SystemDetails.current()
        let destination: URL
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            destination = SupportLinks.email(
                subject: AppStrings.reportProblemSubject, prompt: AppStrings.reportProblemPrompt, details: details
            )
        case .alertSecondButtonReturn:
            destination = SupportLinks.contactPage(details: details)
        default:
            return
        }
        // Whatever was in front goes back to the front before the page or the email opens.
        NSApp.deactivate()
        NSWorkspace.shared.open(destination)
        if showFiles.state == .on {
            showDiagnosticFiles()
        }
    }

    /// Saves the log of this session next to the reports and shows them all in Finder, the
    /// newest first. Reading the log can take a moment, so it happens off the main actor.
    private func showDiagnosticFiles() {
        Task.detached(priority: .userInitiated) { [store, log] in
            do {
                try store.save(Data(Self.sessionLog().utf8), as: .log, at: Date())
            } catch {
                log.error("Could not save the session's log: \(error)")
            }
            store.prune()
            let files = store.files()
            await MainActor.run {
                if files.isEmpty {
                    NSWorkspace.shared.open(store.directory)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting(files)
                }
            }
        }
    }

    /// What Pasto logged since it started, one entry per line. Values logged as private, which
    /// covers anything copied, read `<private>`.
    private nonisolated static func sessionLog() -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(matching: NSPredicate(format: "subsystem == %@", Log.subsystem))
        else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.category)] \(Self.levelName(entry.level)): \(entry.composedMessage)"
        }
        return (SystemDetails.current().lines + [""] + lines).joined(separator: "\n") + "\n"
    }

    private nonisolated static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "log"
        }
    }
}
