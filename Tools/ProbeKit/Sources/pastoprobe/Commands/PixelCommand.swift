import CoreGraphics
import Foundation
import ProbeCore

enum PixelCommand: Command {
    static let name = "pixel"
    static let summary = "Print the sRGB colour of an image pixel or a screen point (or an n×n average)."
    static let usage = """
    pixel --image <file> --at x,y [--size n]      x,y and n in image pixels
           pastoprobe pixel --screen --at x,y [--size n]         x,y and n in screen points
    """
    static let spec = CommandLineArguments.Spec(valueOptions: ["image", "at", "size"], flags: ["screen"])

    private struct Output: Encodable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
        let hex: String
        /// Pixels averaged.
        let samples: Int
    }

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let point = try Geometry.point(parsing: arguments.requiredString("at"))
        let size = try arguments.int("size") ?? 1
        guard size > 0 else { throw ProbeError.usage("--size must be greater than zero") }

        let bitmap: Bitmap
        let center: (x: Int, y: Int)
        let blockSize: Int
        switch (arguments.string("image"), arguments.flag("screen")) {
        case (let path?, false):
            bitmap = try Bitmap(contentsOf: URL(fileURLWithPath: path))
            center = (Int(point.x), Int(point.y))
            blockSize = size
        case (nil, true):
            // Capture just the block of points around the target and average every pixel in it.
            let display = try Displays.display(containing: point)
            let origin = CGDisplayBounds(display).origin
            let half = Double(size / 2)
            let region = Frame(x: point.x - origin.x - half, y: point.y - origin.y - half, w: Double(size), h: Double(size))
            bitmap = try Bitmap(cgImage: await ScreenCapture.image(of: .display(id: display, rect: region)))
            center = (bitmap.width / 2, bitmap.height / 2)
            blockSize = max(bitmap.width, bitmap.height)
        default:
            throw ProbeError.usage("choose exactly one source: --image <file> or --screen")
        }

        guard let average = bitmap.average(centerX: center.x, centerY: center.y, size: blockSize) else {
            throw ProbeError.targetNotFound("\(center.x),\(center.y) is outside the \(bitmap.width)x\(bitmap.height) image")
        }
        let color = average.color.unpremultiplied
        try Console.json(Output(r: color.r, g: color.g, b: color.b, a: color.a, hex: color.hex, samples: average.samples))
    }
}
