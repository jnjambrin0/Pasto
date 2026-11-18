import ProbeCore

enum WindowsCommand: Command {
    static let name = "windows"
    static let summary = "List an app's windows (on screen or not) as the window server sees them."
    static let usage = "windows --app <app> | --all"
    static let spec = CommandLineArguments.Spec(valueOptions: ["app"], flags: ["all"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        if arguments.flag("all") {
            try Console.json(WindowList.all())
        } else {
            try Console.json(WindowList.windows(ofPID: arguments.targetApp().pid))
        }
    }
}
