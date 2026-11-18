import Foundation
import ProbeCore

/// Command-line configuration of the probe window.
struct TargetOptions {
    static let usage = """
    usage: ProbeTarget [--log <path>] [--title <string>] [--frame x,y,w,h] [--fullscreen]
                       [--clear-on-paste] [--copy-source lazy:<ms>] [--floating]
    """

    var logURL: URL
    var title: String
    /// Screen points, top-left origin.
    var frame: Frame?
    var fullscreen: Bool
    var clearOnPaste: Bool
    /// Keeps the window at the floating level, above ordinary windows of other apps (e.g. a terminal
    /// that covers the screen), so a click can reach it and activate the app.
    var floating: Bool
    /// Delay of the lazily provided copy source, when one was requested.
    var lazyCopyDelayMs: Int?

    init(arguments: [String]) throws {
        let spec = CommandLineArguments.Spec(
            valueOptions: ["log", "title", "frame", "copy-source"], flags: ["fullscreen", "clear-on-paste", "floating", "help"]
        )
        let parsed = try CommandLineArguments(arguments, spec: spec)
        try parsed.expectPositionals(0)
        if parsed.flag("help") {
            Console.out(Self.usage)
            exit(0)
        }

        // Without --log every run gets its own file in the per-user temporary directory.
        logURL = parsed.string("log").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("probetarget-\(ProcessInfo.processInfo.processIdentifier).jsonl")
        title = parsed.string("title") ?? "ProbeTarget"
        frame = try parsed.string("frame").map(Frame.init(parsing:))
        fullscreen = parsed.flag("fullscreen")
        clearOnPaste = parsed.flag("clear-on-paste")
        floating = parsed.flag("floating")

        if let source = parsed.string("copy-source") {
            guard source.hasPrefix("lazy:"), let delay = Int(source.dropFirst("lazy:".count)), delay >= 0 else {
                throw ProbeError.usage("--copy-source expects lazy:<milliseconds>, got '\(source)'")
            }
            lazyCopyDelayMs = delay
        }
    }
}
