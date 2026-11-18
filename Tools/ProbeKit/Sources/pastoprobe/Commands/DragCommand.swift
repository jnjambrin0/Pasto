import ProbeCore

enum DragCommand: Command {
    static let name = "drag"
    static let summary = "Drag with the left button between two screen points (needs Accessibility)."
    static let usage = "drag x1,y1 x2,y2 [--duration-ms 300] [--hold-ms 0] [--start-hold-ms 0] [--via x,y --via-hold-ms 0]   --via passes through (and pauses at) a waypoint; --start-hold-ms keeps the button down at x1,y1 first (a press that is then dragged away, which cancels a button)"
    static let spec = CommandLineArguments.Spec(valueOptions: ["duration-ms", "hold-ms", "start-hold-ms", "via", "via-hold-ms"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(2)
        let start = try Geometry.point(parsing: arguments.positional(0, named: "x1,y1"))
        let end = try Geometry.point(parsing: arguments.positional(1, named: "x2,y2"))
        let durationMs = try arguments.nonNegativeInt("duration-ms", default: 300)
        let holdMs = try arguments.nonNegativeInt("hold-ms", default: 0)
        let startHoldMs = try arguments.nonNegativeInt("start-hold-ms", default: 0)
        let via = try arguments.string("via").map(Geometry.point(parsing:))
        let viaHoldMs = try arguments.nonNegativeInt("via-hold-ms", default: 0)
        let downMs = try EventPoster.drag(
            from: start, to: end, durationMs: durationMs, holdMs: holdMs, startHoldMs: startHoldMs, via: via, viaHoldMs: viaHoldMs)
        try Console.json(["durationMs": Double(durationMs), "holdMs": Double(holdMs), "startHoldMs": Double(startHoldMs),
                          "mouseDownContinuousMs": ProbeClock.rounded(downMs)])
    }
}
