import Foundation
import ProbeCore

enum FramesCommand: Command {
    static let name = "frames"
    static let summary = "Record a timestamped PNG frame sequence of a window or display region."
    static let usage = """
    frames (--window <id> | --app <app> --largest | --display main|<index> [--rect x,y,w,h]) \
    --out <dir> [--fps 120] [--duration 2.0]
    """
    static let spec = CommandLineArguments.Spec(
        valueOptions: ["window", "app", "display", "rect", "fps", "duration", "out"], flags: ["largest"]
    )

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let target = try arguments.captureTarget()
        let directory = URL(fileURLWithPath: try arguments.requiredString("out"), isDirectory: true)
        let fps = try arguments.int("fps") ?? 120
        guard (1...240).contains(fps) else { throw ProbeError.usage("--fps must be between 1 and 240") }
        let duration = try arguments.positiveDouble("duration", default: 2)
        let report = try await FrameRecorder.record(target, fps: fps, duration: duration, into: directory)
        try Console.json(report)
        if let failure = report.streamError {
            throw ProbeError.runtime("recording is incomplete: \(failure)")
        }
    }
}
