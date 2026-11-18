import Foundation
import ProbeCore
import Synchronization

/// Appends newline-delimited JSON events to a file. Safe to call from any thread.
final class EventLog: Sendable {
    let url: URL
    private let handle: Mutex<FileHandle>

    init(url: URL) throws {
        self.url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw ProbeError.runtime("cannot create log file \(url.path)")
            }
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            self.handle = Mutex(handle)
        } catch {
            throw ProbeError.runtime("cannot open log file \(url.path): \(error.localizedDescription)")
        }
    }

    /// Writes one event. `time` is on the continuous clock; pass it when the moment that matters
    /// came before the fields could be gathered.
    func record(_ event: String, _ fields: [String: Any] = [:], at time: Double = ProbeClock.continuousMs()) {
        var object = fields
        object["event"] = event
        object["t_ms"] = ProbeClock.rounded(time)
        object["time"] = ProbeClock.isoNow()
        let line = Data((JSONText.line(object) + "\n").utf8)
        handle.withLock { try? $0.write(contentsOf: line) }
    }
}
