import Foundation
import ProbeCore

@main
@MainActor
enum PastoProbe {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
            exit(0)
        } catch let error as ProbeError {
            Console.error("pastoprobe: \(error.message)")
            exit(error.exitCode)
        } catch {
            Console.error("pastoprobe: \(error.localizedDescription)")
            exit(ProbeError.runtime("").exitCode)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let name = arguments.first, !["help", "--help", "-h"].contains(name) else {
            Console.out(overview)
            return
        }
        guard let command = CommandRegistry.all.first(where: { $0.name == name }) else {
            throw ProbeError.usage("unknown subcommand '\(name)'; run 'pastoprobe help' for the list")
        }
        let rest = Array(arguments.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            Console.out("usage: pastoprobe \(command.usage)\n\n\(command.summary)")
            return
        }
        try await command.run(CommandLineArguments(rest, spec: command.spec))
    }

    private static var overview: String {
        // A closure, not a key path: key paths through `any Command.Type` crash the Swift 6.4 compiler.
        let width = CommandRegistry.all.map { $0.name.count }.max() ?? 0
        let lines = CommandRegistry.all.map { command in
            "  \(command.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(command.summary)"
        }
        return """
        pastoprobe: UI automation and measurement probes for Pasto

        usage: pastoprobe <subcommand> [options]    (pastoprobe <subcommand> --help for details)

        \(lines.joined(separator: "\n"))

        exit codes: 0 ok, 1 usage, 2 permission missing, 3 target not found, 4 runtime failure
        """
    }
}
