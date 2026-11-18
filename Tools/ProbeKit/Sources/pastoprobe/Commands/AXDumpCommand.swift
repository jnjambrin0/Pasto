import ProbeCore

enum AXDumpCommand: Command {
    static let name = "ax-dump"
    static let summary = "Dump an app's accessibility tree with frames as JSON (needs Accessibility)."
    static let usage = "ax-dump --app <app> [--window-index N] [--max-depth D] [--max-nodes N] [--no-values]"
    static let spec = CommandLineArguments.Spec(
        valueOptions: ["app", "window-index", "max-depth", "max-nodes"], flags: ["no-values"]
    )

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        try Permissions.requireAccessibility()
        var options = AXWalker.Options()
        options.windowIndex = try arguments.int("window-index")
        options.maxDepth = try arguments.int("max-depth") ?? options.maxDepth
        options.maxNodes = try arguments.int("max-nodes") ?? options.maxNodes
        options.includeValues = !arguments.flag("no-values")
        guard options.maxDepth > 0, options.maxNodes > 0 else {
            throw ProbeError.usage("--max-depth and --max-nodes must be greater than zero")
        }
        try Console.json(AXWalker.dump(app: arguments.targetApp(), options: options))
    }
}
