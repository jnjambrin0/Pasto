import Foundation
import ProbeCore

enum ShotCommand: Command {
    static let name = "shot"
    static let summary = "Capture one window, or a region of a display, as a PNG at native scale."
    static let usage = """
    shot (--window <id> | --app <app> --largest) [--shadow] [--out file.png]
           pastoprobe shot --display main|<index> [--rect x,y,w,h] [--out file.png]
    """
    static let spec = CommandLineArguments.Spec(
        valueOptions: ["window", "app", "display", "rect", "out"], flags: ["largest", "shadow"]
    )

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let target = try arguments.captureTarget()
        if arguments.flag("shadow"), case .display = target {
            throw ProbeError.usage("--shadow applies to window captures only")
        }
        let output = arguments.string("out").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("pastoprobe-shot-\(Int(ProbeClock.continuousMs())).png")
        try Console.json(await ScreenCapture.capture(target, includeShadow: arguments.flag("shadow"), to: output))
    }
}
