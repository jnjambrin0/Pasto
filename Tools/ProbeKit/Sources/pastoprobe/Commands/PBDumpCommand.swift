import AppKit
import ProbeCore

enum PBDumpCommand: Command {
    static let name = "pb-dump"
    static let summary = "Describe the general pasteboard: change count, items, types and byte sizes."
    static let usage = "pb-dump [--content] [--allow-prompt]"
    static let spec = CommandLineArguments.Spec(flags: ["content", "allow-prompt"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        // Listing types is always allowed. Reading the data is what macOS may gate behind a
        // "paste from other apps" alert, so it only happens when that cannot block the tool.
        let behavior = NSPasteboard.general.accessBehavior
        let readData = behavior == .alwaysAllow || (behavior != .alwaysDeny && arguments.flag("allow-prompt"))
        if !readData {
            let name = Permissions.pasteboardAccessName(behavior)
            Console.error(
                behavior == .alwaysDeny
                    ? "pastoprobe: pasteboard access is '\(name)': the system refuses reads, listing types only"
                    : "pastoprobe: pasteboard access is '\(name)': listing types only, because reading sizes could show "
                        + "the system paste alert (pass --allow-prompt to read anyway)"
            )
        }
        try Console.json(PasteboardInspector.snapshot(readData: readData, includeContent: readData && arguments.flag("content")))
    }
}
