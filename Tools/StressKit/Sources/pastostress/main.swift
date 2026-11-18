import Foundation

/// `pastostress`: builds a store the size of a year of heavy use and measures the store and the
/// item list on it.
let usage = """
pastostress — stress bench for Pasto's store and item list

  generate --count N --dir DIR [--seed S] [--image-scale X]
      Fills DIR with a store of N items (70 % short text, 15 % long text, 10 % images,
      5 % links/files/colours, a year of timestamps, 2 000 items on pinboards).
  measure --dir DIR [--label L] [--json FILE]
      Runs every scenario in a process of its own on a copy (APFS clone) of the store in DIR,
      then prints a table and, with --json, writes the results.
  run --count N --work DIR [--label L] [--json FILE] [--regenerate] [--image-scale X]
      generate (unless DIR/store-N already holds one) + measure.
  scenario NAME --store DIR
      One scenario (\(Scenarios.names.joined(separator: ", "))) on the store in DIR; JSON on stdout.
"""

struct Report: Codable {
    var label: String
    var count: Int
    var storeMB: Double
    var generationSeconds: Double
    var scenarios: [ScenarioResult]
}

@MainActor
enum Command {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else {
            print(usage)
            return
        }
        let command = arguments.removeFirst()
        do {
            switch command {
            case "generate":
                let options = try generatorOptions(arguments)
                let directory = URL(filePath: try value(of: "--dir", in: arguments))
                let manifest = try await Generator(options: options).generate(into: directory)
                print("generated \(manifest.count) items in \(Int(manifest.generationSeconds)) s → \(directory.path)")
            case "measure":
                let directory = URL(filePath: try value(of: "--dir", in: arguments))
                try measureAll(directory: directory, label: optionalValue(of: "--label", in: arguments) ?? "", json: optionalValue(of: "--json", in: arguments))
            case "run":
                let options = try generatorOptions(arguments)
                let work = URL(filePath: try value(of: "--work", in: arguments))
                let directory = work.appending(path: "store-\(options.count)")
                let hasStore = FileManager.default.fileExists(atPath: directory.appending(path: "manifest.json").path)
                if !hasStore || arguments.contains("--regenerate") {
                    let manifest = try await Generator(options: options).generate(into: directory)
                    FileHandle.standardError.write(Data("generated \(manifest.count) items in \(Int(manifest.generationSeconds)) s\n".utf8))
                }
                try measureAll(directory: directory, label: optionalValue(of: "--label", in: arguments) ?? "", json: optionalValue(of: "--json", in: arguments))
            case "scenario":
                guard let name = arguments.first else { throw UsageError("scenario needs a name") }
                let directory = URL(filePath: try value(of: "--store", in: arguments))
                let manifest = try loadManifest(in: directory)
                let result = try await Scenarios(directory: directory, manifest: manifest).run(name)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(result))
            default:
                print(usage)
                exit(1)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(4)
        }
        exit(0)
    }

    private static func generatorOptions(_ arguments: [String]) throws -> GeneratorOptions {
        var options = GeneratorOptions()
        if let count = optionalValue(of: "--count", in: arguments) {
            guard let parsed = Int(count.replacingOccurrences(of: "_", with: "")) else { throw UsageError("bad --count") }
            options.count = parsed
        }
        if let seed = optionalValue(of: "--seed", in: arguments), let parsed = UInt64(seed) { options.seed = parsed }
        if let scale = optionalValue(of: "--image-scale", in: arguments), let parsed = Double(scale) { options.imageScale = parsed }
        return options
    }

    private static func value(of flag: String, in arguments: [String]) throws -> String {
        guard let value = optionalValue(of: flag, in: arguments) else { throw UsageError("missing \(flag)") }
        return value
    }

    private static func optionalValue(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func loadManifest(in directory: URL) throws -> Manifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Manifest.self, from: Data(contentsOf: directory.appending(path: "manifest.json")))
    }

    /// Every scenario on its own clone of the store, in a child process: each starts from the
    /// same store and with a clean memory footprint.
    private static func measureAll(directory: URL, label: String, json: String?) throws {
        let manifest = try loadManifest(in: directory)
        let size = Metrics.storeBytes(at: directory.appending(path: "Pasto.sqlite"))
        func run(_ name: String, on store: URL) throws -> ScenarioResult {
            FileHandle.standardError.write(Data("scenario \(name)\n".utf8))
            let process = Process()
            process.executableURL = Bundle.main.executableURL
            process.arguments = ["scenario", name, "--store", store.path]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw UsageError("scenario \(name) failed (\(process.terminationStatus))") }
            return try JSONDecoder().decode(ScenarioResult.self, from: data)
        }

        // The store itself first: a store from an older version is migrated by this open.
        var scenarios = [try run(Scenarios.firstOpen, on: directory)]
        for name in Scenarios.names {
            let clone = directory.deletingLastPathComponent().appending(path: "clone-\(name)-\(UUID().uuidString.prefix(8))")
            try FileManager.default.copyItem(at: directory, to: clone)
            defer { try? FileManager.default.removeItem(at: clone) }
            scenarios.append(try run(name, on: clone))
        }

        let report = Report(
            label: label,
            count: manifest.count,
            storeMB: Double(size.database + size.external) / 1_048_576,
            generationSeconds: manifest.generationSeconds,
            scenarios: scenarios
        )
        print(table(report))
        if let json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: URL(filePath: json))
        }
    }

    private static func table(_ report: Report) -> String {
        func number(_ value: Double?, _ format: String = "%.1f") -> String { value.map { String(format: format, $0) } ?? "" }
        var lines = [
            "N = \(report.count) · store \(String(format: "%.0f", report.storeMB)) MB · \(report.label)",
            "",
            "| scenario | step | wall ms | main CPU ms | applier ms | RSS MB | peak MB | count | disk MB before → after | note |",
            "|---|---|---:|---:|---:|---:|---:|---:|---|---|",
        ]
        for scenario in report.scenarios {
            for step in scenario.steps {
                let disk = step.diskBeforeMB.map { before in "\(number(before, "%.0f")) → \(number(step.diskAfterMB, "%.0f"))" } ?? ""
                lines.append("| \(scenario.scenario) | \(step.name) | \(number(step.wallMs, "%.2f")) | \(number(step.mainCPUms, "%.2f")) | \(number(step.applierMs, "%.2f")) | \(number(step.residentMB, "%.0f")) | \(number(step.peakMB, "%.0f")) | \(step.count.map(String.init) ?? "") | \(disk) | \(step.note ?? "") |")
            }
        }
        return lines.joined(separator: "\n")
    }
}

await Command.main()
