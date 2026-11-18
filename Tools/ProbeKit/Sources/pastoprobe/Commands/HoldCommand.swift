import ProbeCore

/// Holds modifier keys alone (no other key), e.g. ⌘ for a few seconds to reveal shortcut hints.
enum HoldCommand: Command {
    static let name = "hold"
    static let summary = "Hold modifier keys alone, such as cmd, for a while and release them (needs Accessibility)."
    static let usage = "hold <modifiers> [--ms 1500] [--delay-ms 0]   modifiers: cmd, shift, opt, ctrl, fn joined with +"
    static let spec = CommandLineArguments.Spec(valueOptions: ["ms", "delay-ms"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(1)
        let modifiers = try KeyCombo.Modifiers(parsing: arguments.positional(0, named: "modifiers"))
        let holdMs = try arguments.nonNegativeInt("ms", default: 1500)
        let delayMs = try arguments.nonNegativeInt("delay-ms", default: 0)
        try EventPoster.warmUp()
        if delayMs > 0 { ProbeClock.sleep(ms: Double(delayMs)) }
        let times = try EventPoster.hold(modifiers, holdMs: holdMs)
        try Console.json([
            "holdMs": Double(holdMs),
            "downContinuousMs": ProbeClock.rounded(times.downMs),
            "upContinuousMs": ProbeClock.rounded(times.upMs),
        ])
    }
}
