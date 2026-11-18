import ProbeCore

enum KeyCommand: Command {
    static let name = "key"
    static let summary = "Post a key combo such as cmd+shift+v, return or shift+left (needs Accessibility)."
    static let usage = "key <combo> [--hold-ms 20]"
    static let spec = CommandLineArguments.Spec(valueOptions: ["hold-ms"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(1)
        let combo = try KeyCombo(parsing: arguments.positional(0, named: "combo"))
        let holdMs = try arguments.nonNegativeInt("hold-ms", default: 20)
        try Permissions.requirePostEvent()

        let keyCode: UInt16
        switch combo.key {
        case .named(let named):
            keyCode = named.keyCode
        case .character(let character):
            guard let resolved = KeyboardLayout.keyCode(for: character) else {
                throw ProbeError.runtime("the current keyboard layout has no unmodified key for '\(character)'")
            }
            keyCode = resolved
        }
        let keyDownMs = try EventPoster.press(combo, keyCode: keyCode, holdMs: holdMs)
        // `keyDownContinuousMs` is on the clock that `win-poll` and `frames` publish as their origin.
        try Console.json(["keyCode": Double(keyCode), "holdMs": Double(holdMs), "keyDownContinuousMs": ProbeClock.rounded(keyDownMs)])
    }
}
