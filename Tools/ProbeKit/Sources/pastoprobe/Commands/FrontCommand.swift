import AppKit
import ProbeCore

/// Which application is frontmost, once or as a stream of activation events with timestamps.
enum FrontCommand: Command {
    static let name = "front"
    static let summary = "Print the frontmost app; with --watch, a JSON line per app activation/deactivation."
    static let usage = "front [--watch [--duration <seconds>]] | front --activate <pid>"
    static let spec = CommandLineArguments.Spec(valueOptions: ["duration", "activate"], flags: ["watch"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        if let pid = try arguments.int("activate") {
            // For targets without a bundle identifier (ProbeTarget), which `open -a` cannot address.
            guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else {
                throw ProbeError.targetNotFound("no running application with pid \(pid)")
            }
            let accepted = app.activate(options: [.activateAllWindows])
            try await Task.sleep(for: .milliseconds(300))
            var result = describe("front", NSWorkspace.shared.frontmostApplication)
            result["activateAccepted"] = accepted
            Console.out(JSONText.line(result))
            return
        }
        guard arguments.flag("watch") else {
            Console.out(JSONText.line(describe("front", NSWorkspace.shared.frontmostApplication)))
            return
        }
        let duration = try arguments.double("duration")
        let center = NSWorkspace.shared.notificationCenter
        Console.out(JSONText.line(describe("start", NSWorkspace.shared.frontmostApplication)))
        for (name, label) in [
            (NSWorkspace.didActivateApplicationNotification, "didActivate"),
            (NSWorkspace.didDeactivateApplicationNotification, "didDeactivate"),
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let line = JSONText.line(describe(label, app))
                Console.out(line)
            }
        }
        let deadline = duration.map { ProbeClock.continuousMs() + $0 * 1000 }
        while deadline.map({ ProbeClock.continuousMs() < $0 }) ?? true {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private nonisolated static func describe(_ event: String, _ app: NSRunningApplication?) -> [String: Any] {
        [
            "event": event,
            "t_ms": ProbeClock.rounded(ProbeClock.continuousMs()),
            "pid": Int(app?.processIdentifier ?? -1),
            "bundleID": app?.bundleIdentifier ?? "",
            "name": app?.localizedName ?? "",
        ]
    }
}
