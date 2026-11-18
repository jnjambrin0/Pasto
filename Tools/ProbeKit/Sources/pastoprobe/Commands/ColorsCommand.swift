import Foundation
import ProbeCore

enum ColorsCommand: Command {
    static let name = "colors"
    static let summary = "Count the colours inside a rectangle of an image: most frequent, brightest and darkest."
    static let usage = """
    colors --image <file> --rect x,y,w,h [--top 5] [--csv]      x, y, w and h in image pixels
           --csv prints one line per colour: kind,hex[@alpha],count
    """
    static let spec = CommandLineArguments.Spec(valueOptions: ["image", "rect", "top"], flags: ["csv"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let bitmap = try Bitmap(contentsOf: URL(fileURLWithPath: arguments.requiredString("image")))
        let rect = try Frame(parsing: arguments.requiredString("rect"))
        let result = try ColorCensus.census(
            of: bitmap, x: Int(rect.x), y: Int(rect.y), width: Int(rect.w), height: Int(rect.h),
            top: try arguments.nonNegativeInt("top", default: 5)
        )
        guard arguments.flag("csv") else {
            try Console.json(result)
            return
        }
        func line(_ kind: String, _ entry: ColorCensus.Entry) -> String {
            "\(kind),\(entry.hex)\(entry.alpha == 255 ? "" : "@\(entry.alpha)"),\(entry.count)"
        }
        Console.out("pixels,\(result.pixels),distinct,\(result.distinct)")
        for entry in result.top { Console.out(line("top", entry)) }
        Console.out(line("brightest", result.brightest))
        Console.out(line("darkest", result.darkest))
    }
}
