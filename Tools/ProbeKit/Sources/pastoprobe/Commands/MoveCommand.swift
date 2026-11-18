import ProbeCore

enum MoveCommand: Command {
    static let name = "move"
    static let summary = "Move the pointer to a screen point without pressing a button (needs Accessibility)."
    static let usage = "move x,y [--from x0,y0 --duration-ms 200]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["from", "duration-ms"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(1)
        let point = try Geometry.point(parsing: arguments.positional(0, named: "x,y"))
        let start = try arguments.string("from").map(Geometry.point(parsing:))
        let durationMs = try arguments.nonNegativeInt("duration-ms", default: 200)
        let arrivedMs = try EventPoster.move(to: point, from: start, durationMs: durationMs)
        try Console.json(["x": point.x, "y": point.y, "arrivedContinuousMs": ProbeClock.rounded(arrivedMs)])
    }
}
