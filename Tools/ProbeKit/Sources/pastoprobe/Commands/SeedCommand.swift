import Foundation
import ProbeCore

enum SeedCommand: Command {
    static let name = "seed"
    static let summary = "Copy a deterministic sequence of items to the clipboard, one at a time."
    static let usage = "seed --set basic|full [--interval-ms 900] [--fixtures <dir>] [--list]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["set", "interval-ms", "fixtures"], flags: ["list"])

    private struct Output: Encodable {
        struct Item: Encodable {
            let id: String
            let summary: String
            let types: [String]
            /// Pasteboard change count right after the item was written; absent with `--list`.
            let changeCount: Int?
            let t_ms: Double?
        }

        let set: String
        let intervalMs: Int
        let items: [Item]
    }

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let setName = try arguments.requiredString("set")
        guard let set = SeedSet(rawValue: setName) else {
            throw ProbeError.usage("unknown set '\(setName)'; choose basic or full")
        }
        let intervalMs = try arguments.nonNegativeInt("interval-ms", default: 900)
        let fixtures = arguments.string("fixtures").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FixtureFile.defaultDirectory
        let items = set.items

        var written: [Output.Item] = []
        for (index, item) in items.enumerated() {
            var changeCount: Int?
            var time: Double?
            if !arguments.flag("list") {
                changeCount = try SeedWriter.write(item, fixtures: fixtures)
                time = ProbeClock.rounded(ProbeClock.continuousMs())
                Console.error("seeded \(index + 1)/\(items.count) \(item.id)")
                // The pause after each write gives the clipboard manager time to capture it.
                try await Task.sleep(for: .milliseconds(intervalMs))
            }
            written.append(.init(id: item.id, summary: item.summary, types: item.types, changeCount: changeCount, t_ms: time))
        }
        try Console.json(Output(set: set.rawValue, intervalMs: intervalMs, items: written))
    }
}
