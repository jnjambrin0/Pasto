import ProbeCore

enum ScrollCommand: Command {
    static let name = "scroll"
    static let summary = "Post scroll-wheel events at a screen point: vertical and/or horizontal deltas, line or pixel units (needs Accessibility)."
    static let usage = "scroll x,y [--dy 0] [--dx 0] [--pixels] [--count 1] [--interval-ms 16]\n"
        + "       Positive --dy scrolls up, positive --dx scrolls left (content moves right). Line units unless --pixels."
    static let spec = CommandLineArguments.Spec(valueOptions: ["dy", "dx", "count", "interval-ms"], flags: ["pixels"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(1)
        let point = try Geometry.point(parsing: arguments.positional(0, named: "x,y"))
        let deltaY = try arguments.int("dy") ?? 0
        let deltaX = try arguments.int("dx") ?? 0
        let count = try arguments.int("count") ?? 1
        guard count >= 1 else { throw ProbeError.usage("--count must be at least 1") }
        let intervalMs = try arguments.nonNegativeInt("interval-ms", default: 16)
        let firstAt = try EventPoster.scroll(
            at: point, deltaX: Int32(deltaX), deltaY: Int32(deltaY), pixels: arguments.flag("pixels"), count: count,
            intervalMs: intervalMs)
        try Console.json([
            "dx": Double(deltaX), "dy": Double(deltaY), "count": Double(count),
            "firstEventContinuousMs": ProbeClock.rounded(firstAt),
        ])
    }
}
