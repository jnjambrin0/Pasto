import Foundation
import ProbeCore

/// Stacks images (or crops of them) top to bottom with a thin separator, to look at a frame
/// sequence in one picture.
enum StackCommand: Command {
    static let name = "stack"
    static let summary = "Stack images, or the same crop of each, top to bottom into one PNG (for viewing frame sequences)."
    static let usage = "stack <image>... --out <file.png> [--crop x,y,w,h]   crop in image pixels"
    static let spec = CommandLineArguments.Spec(valueOptions: ["out", "crop"])

    static func run(_ arguments: CommandLineArguments) async throws {
        guard !arguments.positionals.isEmpty else { throw ProbeError.usage("give at least one image") }
        let crop = try arguments.string("crop").map(Frame.init(parsing:))
        var parts: [Bitmap] = []
        for path in arguments.positionals {
            let image = try Bitmap(contentsOf: URL(fileURLWithPath: path))
            guard let crop else { parts.append(image); continue }
            let x0 = max(0, Int(crop.x)), y0 = max(0, Int(crop.y))
            let w = min(Int(crop.w), image.width - x0), h = min(Int(crop.h), image.height - y0)
            guard w > 0, h > 0 else { throw ProbeError.usage("--crop lies outside \(path)") }
            var piece = Bitmap(width: w, height: h, fill: RGBA(r: 0, g: 0, b: 0))
            for y in 0..<h { for x in 0..<w { piece[x, y] = image[x0 + x, y0 + y] } }
            parts.append(piece)
        }
        let separator = 2
        let width = parts.map(\.width).max() ?? 1
        let height = parts.map(\.height).reduce(0, +) + separator * (parts.count - 1)
        var canvas = Bitmap(width: width, height: height, fill: RGBA(r: 255, g: 0, b: 255))
        var top = 0
        for part in parts {
            for y in 0..<part.height { for x in 0..<part.width { canvas[x, top + y] = part[x, y] } }
            top += part.height + separator
        }
        let out = URL(fileURLWithPath: try arguments.requiredString("out"))
        try PNGFile.write(try canvas.makeCGImage(), to: out)
        Console.out("\(out.path) \(width)x\(height)")
    }
}
