import Foundation
import ProbeCore

/// Reads a `frames` recording back as a time series: point colours, an edge position and the
/// progress of a region between its first and last look, one CSV row per frame.
enum TraceCommand: Command {
    static let name = "trace"
    static let summary = "Turn a frames recording into a CSV time series: point colours, edge position, region progress."
    static let usage = """
    trace <frames-dir> [--points x,y:x,y...] [--size 1]
                             [--edge col:x:from:to | row:y:from:to --bg #RRGGBB [--tolerance 8] [--from-end]]
                             [--progress x,y,w,h:x,y,w,h...] [--start first|<ms>] [--end last|<ms>] [--changed-only]
           All coordinates in image pixels. --points prints each point's colour (n×n mean with --size).
           --edge prints where the first pixel unlike --bg sits along the line (scanning backwards with --from-end).
           --progress prints, per rectangle, k in frame ≈ start + k·(end − start): 0 at the start frame, 1 at the end
           frame (for a cross-fade, the incoming opacity). --start/--end pick the reference frames by t_ms (nearest).
           --changed-only skips frames identical to the previous one in every printed column.
    """
    static let spec = CommandLineArguments.Spec(
        valueOptions: ["points", "size", "edge", "bg", "tolerance", "progress", "start", "end"],
        flags: ["from-end", "changed-only"]
    )

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(1)
        let directory = URL(fileURLWithPath: try arguments.positional(0, named: "frames-dir"), isDirectory: true)
        let entries = try FrameTrace.index(of: directory)
        guard !entries.isEmpty else { throw ProbeError.runtime("the recording has no frames") }

        let points = try (arguments.string("points") ?? "").split(separator: ":").map { try Geometry.point(parsing: String($0)) }
        let size = max(1, try arguments.nonNegativeInt("size", default: 1))
        let rects = try (arguments.string("progress") ?? "").split(separator: ":").map { try Frame(parsing: String($0)) }
        let edge = try parseEdge(arguments)
        guard !points.isEmpty || !rects.isEmpty || edge != nil else {
            throw ProbeError.usage("ask for at least one of --points, --edge or --progress")
        }

        func load(_ entry: FrameTrace.IndexEntry) throws -> Bitmap {
            try Bitmap(contentsOf: directory.appendingPathComponent(entry.file))
        }
        func nearest(_ option: String, fallback: FrameTrace.IndexEntry) throws -> FrameTrace.IndexEntry {
            guard let text = arguments.string(option), text != "first", text != "last" else {
                return arguments.string(option) == "first" ? entries[0] : (arguments.string(option) == "last" ? entries[entries.count - 1] : fallback)
            }
            guard let target = Double(text) else { throw ProbeError.usage("--\(option) takes first, last or a t_ms value") }
            return entries.min { abs($0.milliseconds - target) < abs($1.milliseconds - target) }!
        }
        let startImage = rects.isEmpty ? nil : try load(nearest("start", fallback: entries[0]))
        let endImage = rects.isEmpty ? nil : try load(nearest("end", fallback: entries[entries.count - 1]))

        var header = ["t_ms"]
        header += points.indices.map { "p\($0)" }
        if edge != nil { header.append("edge") }
        header += rects.indices.map { "k\($0)" }
        Console.out(header.joined(separator: ","))

        var previous: [String]?
        for entry in entries {
            let bitmap = try load(entry)
            var columns: [String] = []
            for point in points {
                let sample = bitmap.average(centerX: Int(point.x), centerY: Int(point.y), size: size)
                columns.append(sample.map { $0.color.unpremultiplied.hex } ?? "-")
            }
            if let edge {
                columns.append(try FrameTrace.edge(edge, in: bitmap).map(String.init) ?? "-")
            }
            if let startImage, let endImage {
                for rect in rects {
                    let value = FrameTrace.progress(
                        bitmap, start: startImage, end: endImage,
                        rect: (Int(rect.x), Int(rect.y), Int(rect.w), Int(rect.h)))
                    columns.append(value.map { String(format: "%.3f", $0) } ?? "-")
                }
            }
            if arguments.flag("changed-only"), columns == previous { continue }
            previous = columns
            Console.out(([String(format: "%.1f", entry.milliseconds)] + columns).joined(separator: ","))
        }
    }

    private static func parseEdge(_ arguments: CommandLineArguments) throws -> FrameTrace.Edge? {
        guard let text = arguments.string("edge") else { return nil }
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count == 4, let line = Int(parts[1]), let from = Int(parts[2]), let to = Int(parts[3]), from < to else {
            throw ProbeError.usage("--edge takes col:x:from:to or row:y:from:to")
        }
        let axis: Scanline.Axis = switch parts[0] {
        case "col": .column(line)
        case "row": .row(line)
        default: throw ProbeError.usage("--edge must start with col or row")
        }
        guard let hex = arguments.string("bg") else { throw ProbeError.usage("--edge needs --bg #RRGGBB") }
        return FrameTrace.Edge(
            axis: axis, range: from..<to, background: try parseHex(hex),
            tolerance: try arguments.nonNegativeInt("tolerance", default: 8), fromEnd: arguments.flag("from-end"))
    }

    static func parseHex(_ text: String) throws -> RGBA {
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            throw ProbeError.usage("expected a colour like #RRGGBB but got '\(text)'")
        }
        return RGBA(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
    }
}
