import ProbeCore

enum TypeCommand: Command {
    static let name = "type"
    static let summary = "Type a string as Unicode key events (needs Accessibility)."
    static let usage = "type <text> [--interval-ms 15]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["interval-ms"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(1)
        let text = try arguments.positional(0, named: "text")
        let intervalMs = try arguments.nonNegativeInt("interval-ms", default: 15)
        try EventPoster.type(text, intervalMs: intervalMs)
        try Console.json(["characters": text.count, "intervalMs": intervalMs])
    }
}
