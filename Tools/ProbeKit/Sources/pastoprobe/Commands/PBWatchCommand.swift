import AppKit
import ProbeCore

enum PBWatchCommand: Command {
    static let name = "pb-watch"
    static let summary = "Print a JSON line whenever the general pasteboard's change count moves."
    static let usage = "pb-watch [--hz 20] [--duration <seconds>]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["hz", "duration"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let period = 1000 / (try arguments.positiveDouble("hz", default: 20))
        let deadline = try arguments.double("duration").map { ProbeClock.continuousMs() + $0 * 1000 }
        let pasteboard = NSPasteboard.general

        var lastChangeCount = pasteboard.changeCount
        report("start", pasteboard)
        while deadline.map({ ProbeClock.continuousMs() < $0 }) ?? true {
            try await Task.sleep(for: .milliseconds(period))
            guard pasteboard.changeCount != lastChangeCount else { continue }
            lastChangeCount = pasteboard.changeCount
            report("change", pasteboard)
        }
    }

    /// Types only: reading them needs no permission and does not resolve promised data.
    private static func report(_ event: String, _ pasteboard: NSPasteboard) {
        Console.out(JSONText.line([
            "event": event,
            "t_ms": ProbeClock.rounded(ProbeClock.continuousMs()),
            "time": ProbeClock.isoNow(),
            "changeCount": pasteboard.changeCount,
            "items": (pasteboard.pasteboardItems ?? []).map { $0.types.map(\.rawValue) },
        ]))
    }
}
