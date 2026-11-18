import ProbeCore

enum ClickCommand: Command {
    static let name = "click"
    static let summary = "Click at a screen point, optionally several times, with the right button or holding modifiers (needs Accessibility)."
    static let usage = "click x,y [--count 2] [--right] [--mods cmd+shift] [--down-ms 30]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["count", "mods", "down-ms"], flags: ["right"])

    private struct Output: Encodable {
        let x: Double
        let y: Double
        let count: Int
        let button: String
        let mouseDownContinuousMs: Double
    }

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(1)
        let point = try Geometry.point(parsing: arguments.positional(0, named: "x,y"))
        let count = try arguments.int("count") ?? 1
        guard (1...5).contains(count) else { throw ProbeError.usage("--count must be between 1 and 5") }
        // Reuse the combo parser: "--mods cmd+shift" is parsed as the combo "cmd+shift+a".
        let modifiers = try arguments.string("mods").map { try KeyCombo(parsing: $0 + "+a").modifiers } ?? []
        let downMs = try arguments.nonNegativeInt("down-ms", default: 30)
        let downAt = try EventPoster.click(
            at: point, count: count, right: arguments.flag("right"), modifiers: modifiers, downMs: downMs)
        try Console.json(Output(
            x: point.x, y: point.y, count: count, button: arguments.flag("right") ? "right" : "left",
            mouseDownContinuousMs: ProbeClock.rounded(downAt)))
    }
}
