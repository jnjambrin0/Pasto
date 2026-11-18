import Foundation
import ProbeCore

enum FileWatchCommand: Command {
    static let name = "file-watch"
    static let summary = "Print a JSON line whenever a file is written, extended, renamed or deleted."
    static let usage = "file-watch <path> [--duration <seconds>]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["duration"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(1)
        let path = try arguments.positional(0, named: "path")
        let duration = try arguments.double("duration")
        let watcher = FileWatcher(path: path)
        guard watcher.open() else { throw ProbeError.targetNotFound("cannot open \(path)") }
        watcher.report(["start"])
        if let duration {
            try await Task.sleep(for: .seconds(duration))
        } else {
            while true { try await Task.sleep(for: .seconds(3600)) }
        }
    }
}

/// Watches one path with a vnode dispatch source. When the file is deleted or renamed away
/// (SQLite does this to `-wal` files) it keeps retrying until a file exists at the path again.
@MainActor
private final class FileWatcher {
    private let path: String
    private var source: DispatchSourceFileSystemObject?

    init(path: String) {
        self.path = path
    }

    func open() -> Bool {
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handle(source.data) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        return true
    }

    private func handle(_ events: DispatchSource.FileSystemEvent) {
        var names: [String] = []
        if events.contains(.write) { names.append("write") }
        if events.contains(.extend) { names.append("extend") }
        if events.contains(.rename) { names.append("rename") }
        if events.contains(.delete) { names.append("delete") }
        report(names)
        if events.contains(.delete) || events.contains(.rename) {
            source?.cancel()
            source = nil
            reopen()
        }
    }

    private func reopen() {
        if open() {
            report(["reopened"])
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                MainActor.assumeIsolated { self?.reopen() }
            }
        }
    }

    func report(_ events: [String]) {
        var line: [String: Any] = [
            "events": events,
            "t_ms": ProbeClock.rounded(ProbeClock.continuousMs()),
            "time": ProbeClock.isoNow(),
        ]
        if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int {
            line["size"] = size
        }
        Console.out(JSONText.line(line))
    }
}
