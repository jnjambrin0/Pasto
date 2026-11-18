import Foundation
import ProbeCore

enum ImgDiffCommand: Command {
    static let name = "imgdiff"
    static let summary = "Compare two images pixel by pixel in sRGB; optionally write a heat map."
    static let usage = "imgdiff <a.png> <b.png> [--threshold 2] [--crop-common] [--out diff.png]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["threshold", "out"], flags: ["crop-common"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(2)
        let a = try Bitmap(contentsOf: URL(fileURLWithPath: arguments.positional(0, named: "a.png")))
        let b = try Bitmap(contentsOf: URL(fileURLWithPath: arguments.positional(1, named: "b.png")))
        let threshold = try arguments.int("threshold") ?? 2
        guard (0...255).contains(threshold) else { throw ProbeError.usage("--threshold must be between 0 and 255") }
        let cropCommon = arguments.flag("crop-common")

        guard let output = arguments.string("out") else {
            try Console.json(ImageDiff.compare(a, b, threshold: threshold, cropCommon: cropCommon))
            return
        }
        let (result, heatmap) = try ImageDiff.compareWithHeatmap(a, b, threshold: threshold, cropCommon: cropCommon)
        try PNGFile.write(heatmap.makeCGImage(), to: URL(fileURLWithPath: output))
        try Console.json(result)
    }
}
