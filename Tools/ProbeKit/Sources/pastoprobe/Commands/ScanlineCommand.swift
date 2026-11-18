import Foundation
import ProbeCore

enum ScanlineCommand: Command {
    static let name = "scanline"
    static let summary = "List the runs of near-constant colour along a row or column of one or more images."
    static let usage = """
    scanline (--image <file> | <file>...) (--row y | --col x) [--from a] [--to b] [--tolerance 0]
                              [--min-run 1] [--against <ref.png>] [--csv]
           y, x, a and b in image pixels (b exclusive). --min-run merges shorter runs into one
           colourless stretch. --against reports where the line differs from the same line of a
           reference image instead of listing runs. --csv prints one compact line per run.
    """
    static let spec = CommandLineArguments.Spec(
        valueOptions: ["image", "row", "col", "from", "to", "tolerance", "min-run", "against"], flags: ["csv"]
    )

    private struct Output: Encodable {
        let image: String
        let axis: String
        let line: Int
        let runs: [Scanline.Run]?
        let difference: Scanline.Difference?
    }

    static func run(_ arguments: CommandLineArguments) async throws {
        let paths = (arguments.string("image").map { [$0] } ?? []) + arguments.positionals
        guard !paths.isEmpty else { throw ProbeError.usage("give at least one image") }
        let axis: Scanline.Axis
        switch (try arguments.int("row"), try arguments.int("col")) {
        case (let y?, nil): axis = .row(y)
        case (nil, let x?): axis = .column(x)
        default: throw ProbeError.usage("choose exactly one of --row y or --col x")
        }
        let tolerance = try arguments.nonNegativeInt("tolerance", default: 0)
        let minRun = max(1, try arguments.nonNegativeInt("min-run", default: 1))
        let range: Range<Int>? = switch (try arguments.int("from"), try arguments.int("to")) {
        case (nil, nil): nil
        case (let from, let to): (from ?? 0)..<max((from ?? 0), to ?? Int.max)
        }
        let reference = try arguments.string("against").map { try Bitmap(contentsOf: URL(fileURLWithPath: $0)) }
        let (axisName, line) = switch axis {
        case .row(let y): ("row", y)
        case .column(let x): ("col", x)
        }

        var outputs: [Output] = []
        for path in paths {
            let bitmap = try Bitmap(contentsOf: URL(fileURLWithPath: path))
            let (offset, pixels) = try Scanline.pixels(of: bitmap, along: axis, range: range)
            if let reference {
                let (_, other) = try Scanline.pixels(of: reference, along: axis, range: range)
                let difference = Scanline.difference(pixels, other, offset: offset, tolerance: tolerance)
                outputs.append(Output(image: path, axis: axisName, line: line, runs: nil, difference: difference))
            } else {
                let runs = Scanline.runs(pixels, offset: offset, tolerance: tolerance, minRun: minRun)
                outputs.append(Output(image: path, axis: axisName, line: line, runs: runs, difference: nil))
            }
        }

        guard arguments.flag("csv") else {
            try Console.json(outputs)
            return
        }
        for output in outputs {
            let prefix = paths.count > 1 ? "\((output.image as NSString).lastPathComponent)," : ""
            if reference != nil {
                let difference = output.difference
                Console.out("\(prefix)\(difference.map { "\($0.first),\($0.last),\($0.count)" } ?? "-,-,0")")
            }
            for run in output.runs ?? [] {
                let colour = run.hex.map { run.alpha == 255 ? $0 : "\($0)@\(run.alpha ?? 0)" } ?? "mixed(\(run.pieces))"
                Console.out("\(prefix)\(run.start),\(run.end),\(run.length),\(colour)")
            }
        }
    }
}
