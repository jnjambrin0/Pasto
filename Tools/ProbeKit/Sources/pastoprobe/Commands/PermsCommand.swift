import ProbeCore

enum PermsCommand: Command {
    static let name = "perms"
    static let summary = "Print which privacy permissions the responsible process (your terminal) holds."
    static let usage = "perms"
    static let spec = CommandLineArguments.Spec()

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        try Console.json(Permissions.current())
    }
}
