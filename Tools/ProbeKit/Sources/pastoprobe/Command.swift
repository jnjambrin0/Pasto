import Foundation
import ProbeCore

/// One subcommand. Results go to standard output, failures are thrown as `ProbeError`.
@MainActor
protocol Command {
    static var name: String { get }
    static var summary: String { get }
    /// Synopsis shown by `--help`, starting with the subcommand name.
    static var usage: String { get }
    static var spec: CommandLineArguments.Spec { get }
    static func run(_ arguments: CommandLineArguments) async throws
}

@MainActor
enum CommandRegistry {
    static let all: [any Command.Type] = [
        WindowsCommand.self, WinPollCommand.self, AXDumpCommand.self, AXDiffCommand.self, AXMenuCommand.self,
        ShotCommand.self, FramesCommand.self, ImgDiffCommand.self, PixelCommand.self, ScanlineCommand.self, ColorsCommand.self,
        KeyCommand.self, KeysCommand.self, TypeCommand.self, ClickCommand.self, MoveCommand.self, DragCommand.self, ScrollCommand.self,
        SeedCommand.self, PBDumpCommand.self, PBWatchCommand.self, FileWatchCommand.self,
        BackdropCommand.self, FrontCommand.self, PermsCommand.self, TraceCommand.self, HoldCommand.self, StackCommand.self,
    ]
}

extension CommandLineArguments {
    /// The app named by `--app`.
    func targetApp() throws -> TargetApp {
        try TargetApp.resolve(requiredString("app"))
    }

    /// The window named by `--window <id>` or by `--app X --largest`.
    func targetWindow() throws -> WindowInfo {
        if let id = try int("window") {
            guard let windowID = UInt32(exactly: id), let window = WindowList.window(id: windowID) else {
                throw ProbeError.targetNotFound("no window with id \(id)")
            }
            return window
        }
        guard string("app") != nil, flag("largest") else {
            throw ProbeError.usage("choose a window with --window <id> or --app <app> --largest")
        }
        return try WindowList.largest(of: targetApp())
    }

    /// What `--window`, `--app X --largest` or `--display D [--rect x,y,w,h]` selects for capture.
    func captureTarget() throws -> CaptureTarget {
        if let display = string("display") {
            return .display(id: try Displays.resolve(display), rect: try string("rect").map(Frame.init(parsing:)))
        }
        guard string("rect") == nil else { throw ProbeError.usage("--rect needs --display") }
        return .window(id: try targetWindow().id)
    }
}
