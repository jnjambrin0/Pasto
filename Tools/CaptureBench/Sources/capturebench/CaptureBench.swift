import Foundation

/// `capturebench <command> [options]`. Every measuring command runs in a process of its own, so
/// that the peak memory it reports is its own.
@main
struct CaptureBench {
    static let usage = """
    capturebench — what heavy content costs Pasto (build with -c release)

      suite [--sizes 1,50,300,900] [--kinds text,image,data,tiff]
                                     capture every kind and size, then restore the 300 MB ones,
                                     each in a process of its own; prints a table
      prepare --kind K --mb N        make the payload files only
      capture --kind K --mb N [--then-small] [--store DIR]
                                     copy a payload once and wait for it in the history
      phases --kind K --mb N         time building the item and storing it, apart
      restore --store DIR --item ID  paste an item of a store a capture run left
      index-read --store DIR --item ID
                                     read that item as the search indexer does
      thumbnails [--count 5000] [--rate 120] [--limit-mb N]
                                     scroll a strip of image cards through the shared decoder
      search-fill --docs N [--from M] [--pause-ms P]
                                     fill the benchmark's private Spotlight index (empties it
                                     first unless --from), P ms between batches of 1000
      search-count                   how many items the index finds
      search-query --docs N [--repeats 5]
                                     time the probes against that index
      search-clean                   delete the benchmark's index
      idle [--seconds 60] [--no-monitoring] [--leeway-ms N]
                                     CPU and wakeups at rest
      link-compare [--urls FILE]     link previews from Link Presentation and from Pasto's
                                     own reader, side by side (a URL per line; default: 28)

    Options shared by all: --dir DIR (payloads and stores; default $TMPDIR/capturebench).
    """

    @MainActor
    static func main() async {
        // Progress lines reach a file as they are printed.
        setvbuf(stdout, nil, _IOLBF, 0)
        let arguments = Arguments(CommandLine.arguments.dropFirst())
        let workDirectory = arguments.value("--dir").map { URL(filePath: $0) }
            ?? URL.temporaryDirectory.appending(path: "capturebench", directoryHint: .isDirectory)
        let payloads = workDirectory.appending(path: "payloads", directoryHint: .isDirectory)
        do {
            switch arguments.command {
            case "suite":
                try await Suite.run(
                    sizes: arguments.list("--sizes")?.compactMap { Int($0) } ?? [1, 50, 300, 900],
                    kinds: arguments.list("--kinds")?.compactMap(PayloadKind.init(rawValue:)) ?? [.text, .image, .data],
                    workDirectory: workDirectory
                )
            case "prepare":
                let payload = try Payload.prepared(try arguments.kind(), megabytes: try arguments.megabytes(), in: payloads)
                print("\(payload.kind.rawValue) \(payload.megabytes) MB: \(payload.representations.map(\.file.path))")
            case "capture":
                let store = arguments.value("--store").map { URL(filePath: $0) }
                    ?? workDirectory.appending(path: "stores/\(UUID().uuidString)", directoryHint: .isDirectory)
                try await CaptureScenario.run(
                    kind: try arguments.kind(),
                    megabytes: try arguments.megabytes(),
                    payloads: payloads,
                    storeDirectory: store,
                    followedBySmallCopy: arguments.flag("--then-small")
                )
            case "phases":
                try await CaptureScenario.phases(
                    kind: try arguments.kind(),
                    megabytes: try arguments.megabytes(),
                    payloads: payloads,
                    storeDirectory: workDirectory.appending(path: "stores/\(UUID().uuidString)", directoryHint: .isDirectory)
                )
            case "restore":
                guard let store = arguments.value("--store"), let item = arguments.value("--item") else { throw BenchError(usage) }
                try await RestoreScenario.run(storeDirectory: URL(filePath: store), item: item)
            case "index-read":
                guard let store = arguments.value("--store"), let item = arguments.value("--item") else { throw BenchError(usage) }
                try await RestoreScenario.indexRead(storeDirectory: URL(filePath: store), item: item)
            case "thumbnails":
                try await ThumbnailScenario.run(
                    count: arguments.value("--count").flatMap { Int($0) } ?? 5000,
                    cardsPerSecond: arguments.value("--rate").flatMap { Double($0) } ?? 120,
                    byteLimit: arguments.value("--limit-mb").flatMap { Int($0) }.map { $0 * 1_048_576 }
                )
            case "search-fill":
                try await SearchScenario.fill(
                    total: arguments.value("--docs").flatMap { Int($0) } ?? 100_000,
                    from: arguments.value("--from").flatMap { Int($0) } ?? 0,
                    pause: .milliseconds(arguments.value("--pause-ms").flatMap { Int($0) } ?? 0)
                )
            case "search-count":
                try await SearchScenario.count()
            case "search-query":
                try await SearchScenario.query(
                    documents: arguments.value("--docs").flatMap { Int($0) } ?? 0,
                    repeats: arguments.value("--repeats").flatMap { Int($0) } ?? 5
                )
            case "search-clean":
                try await SearchScenario.clean()
            case "idle":
                try await IdleScenario.run(
                    seconds: arguments.value("--seconds").flatMap { Int($0) } ?? 60,
                    monitoring: !arguments.flag("--no-monitoring"),
                    leewayMilliseconds: arguments.value("--leeway-ms").flatMap { Int($0) }
                )
            case "link-compare":
                try await LinkCompareScenario.run(urlsFile: arguments.value("--urls"))
            default:
                print(usage)
            }
        } catch {
            FileHandle.standardError.write(Data("capturebench: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}

struct Arguments {
    let command: String?
    private let rest: [String]

    init(_ arguments: ArraySlice<String>) {
        command = arguments.first
        rest = Array(arguments.dropFirst())
    }

    func value(_ name: String) -> String? {
        guard let index = rest.firstIndex(of: name), rest.indices.contains(index + 1) else { return nil }
        return rest[index + 1]
    }

    func list(_ name: String) -> [String]? {
        value(name)?.split(separator: ",").map(String.init)
    }

    func flag(_ name: String) -> Bool {
        rest.contains(name)
    }

    func kind() throws -> PayloadKind {
        guard let kind = value("--kind").flatMap(PayloadKind.init(rawValue:)) else { throw BenchError("--kind text|image|data|tiff") }
        return kind
    }

    func megabytes() throws -> Int {
        guard let megabytes = value("--mb").flatMap({ Int($0) }) else { throw BenchError("--mb N") }
        return megabytes
    }
}

/// Runs measuring commands in child processes and gathers what they print.
enum Suite {
    static func run(sizes: [Int], kinds: [PayloadKind], workDirectory: URL) async throws {
        let payloads = workDirectory.appending(path: "payloads", directoryHint: .isDirectory)
        print("Preparing payloads in \(payloads.path)…")
        for kind in kinds {
            for size in sizes {
                _ = try Payload.prepared(kind, megabytes: size, in: payloads)
            }
        }
        print("kind  | MB  | latency ms | read ms | after read ms | heap peak Δ | heap/payload | resident peak Δ | resident/payload | heap retained | resident retained | small after ms")
        var restorable: [(kind: PayloadKind, store: String, item: String)] = []
        for kind in kinds {
            for size in sizes {
                let store = workDirectory.appending(path: "stores/\(kind.rawValue)-\(size)", directoryHint: .isDirectory)
                try? FileManager.default.removeItem(at: store)
                let result = try child([
                    "capture", "--kind", kind.rawValue, "--mb", String(size), "--then-small",
                    "--store", store.path, "--dir", workDirectory.path,
                ])
                let values = result.values
                print(String(
                    format: "%-5@ | %3d | %10.0f | %7.0f | %13.0f | %11.0f | %12.2f | %15.0f | %16.2f | %13.0f | %17.0f | %14.0f",
                    kind.rawValue, size, values["latency_ms"] ?? -1, values["read_ms"] ?? -1, values["after_read_ms"] ?? -1,
                    values["heap_peak_delta_mb"] ?? -1, values["heap_peak_ratio"] ?? -1, values["peak_delta_mb"] ?? -1,
                    values["peak_ratio"] ?? -1, values["retained_heap_mb"] ?? -1, values["retained_mb"] ?? -1,
                    values["small_latency_ms"] ?? -1
                ))
                if size == 300, let item = result.notes["item"] {
                    restorable.append((kind, store.path, item))
                }
            }
        }
        guard !restorable.isEmpty else { return }
        print("\nrestore 300 MB | main thread ms | file URL ms | heap peak Δ | resident peak Δ | heap retained | temp files | images folder")
        for entry in restorable {
            let result = try child(["restore", "--store", entry.store, "--item", entry.item])
            let values = result.values
            print(String(
                format: "%-14@ | %14.0f | %11.0f | %11.0f | %15.0f | %13.0f | %10.0f | %@",
                entry.kind.rawValue, values["main_thread_ms"] ?? -1, values["file_url_ms"] ?? -1, values["heap_peak_delta_mb"] ?? -1,
                values["peak_delta_mb"] ?? -1, values["retained_heap_mb"] ?? -1, values["temporary_files"] ?? -1,
                result.notes["images_folder_mode"] ?? "-"
            ))
        }
        print("\nindex read 300 MB | ms | heap peak Δ | footprint peak Δ | heap retained | characters")
        for entry in restorable {
            let values = try child(["index-read", "--store", entry.store, "--item", entry.item]).values
            print(String(
                format: "%-17@ | %4.0f | %11.0f | %16.0f | %13.0f | %10.0f",
                entry.kind.rawValue, values["read_ms"] ?? -1, values["heap_peak_delta_mb"] ?? -1,
                values["footprint_peak_delta_mb"] ?? -1, values["retained_heap_mb"] ?? -1, values["text_characters"] ?? -1
            ))
        }
    }

    struct ChildResult: Decodable {
        var scenario: String
        var values: [String: Double]
        var notes: [String: String]
    }

    private static func child(_ arguments: [String]) throws -> ChildResult {
        let process = Process()
        process.executableURL = URL(filePath: CommandLine.arguments[0])
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard let line = text.split(separator: "\n").last(where: { $0.hasPrefix("RESULT ") }) else {
            throw BenchError("\(arguments.joined(separator: " ")) printed no result:\n\(text)")
        }
        return try JSONDecoder().decode(ChildResult.self, from: Data(line.dropFirst("RESULT ".count).utf8))
    }
}
