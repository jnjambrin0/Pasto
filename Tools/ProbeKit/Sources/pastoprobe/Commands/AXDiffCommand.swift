import Foundation
import ProbeCore

enum AXDiffCommand: Command {
    static let name = "ax-diff"
    static let summary = "Compare two ax-dump files: frame deltas, missing and extra nodes."
    static let usage = "ax-diff <a.json> <b.json> [--tolerance 0.5]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["tolerance"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(2)
        let a = try load(arguments.positional(0, named: "a.json"))
        let b = try load(arguments.positional(1, named: "b.json"))
        let tolerance = try arguments.double("tolerance") ?? 0.5
        guard tolerance >= 0 else { throw ProbeError.usage("--tolerance must not be negative") }
        try Console.json(AXDiff.compare(a.root, b.root, tolerance: tolerance))
    }

    private static func load(_ path: String) throws -> AXDump {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ProbeError.targetNotFound("cannot read \(path)")
        }
        do {
            return try JSONDecoder().decode(AXDump.self, from: data)
        } catch {
            throw ProbeError.runtime("\(path) is not an ax-dump file: \(error.localizedDescription)")
        }
    }
}
