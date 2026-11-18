import ProbeCore

/// Several key combos from one process, each at a set offset from the first, so that presses
/// closer together than a process launch (≈ 130 ms) can be measured.
enum KeysCommand: Command {
    static let name = "keys"
    static let summary = "Post several key combos in one process at given offsets: keys cmd+shift+v@0 return@60 (needs Accessibility)."
    static let usage = "keys <combo>[@offset-ms]... [--gap-ms 100] [--hold-ms 20]\n"
        + "       Without @offset a combo follows the previous key-down by --gap-ms. Offsets count from the first key-down."
    static let spec = CommandLineArguments.Spec(valueOptions: ["gap-ms", "hold-ms"])

    private struct Press: Encodable {
        let combo: String
        let keyCode: Int
        let requestedOffsetMs: Double
        let keyDownContinuousMs: Double
    }

    static func run(_ arguments: CommandLineArguments) async throws {
        guard !arguments.positionals.isEmpty else { throw ProbeError.usage("missing <combo>") }
        let gapMs = Double(try arguments.nonNegativeInt("gap-ms", default: 100))
        let holdMs = try arguments.nonNegativeInt("hold-ms", default: 20)
        try Permissions.requirePostEvent()

        var plan: [(text: String, combo: KeyCombo, keyCode: UInt16, offset: Double)] = []
        var previousOffset = -gapMs
        for token in arguments.positionals {
            let parts = token.split(separator: "@", maxSplits: 1).map(String.init)
            let combo = try KeyCombo(parsing: parts[0])
            let offset: Double
            if parts.count == 2 {
                guard let value = Double(parts[1]), value >= 0 else { throw ProbeError.usage("bad offset in '\(token)'") }
                offset = value
            } else {
                offset = previousOffset + gapMs
            }
            previousOffset = offset
            let keyCode: UInt16
            switch combo.key {
            case .named(let named): keyCode = named.keyCode
            case .character(let character):
                guard let resolved = KeyboardLayout.keyCode(for: character) else {
                    throw ProbeError.runtime("the current keyboard layout has no unmodified key for '\(character)'")
                }
                keyCode = resolved
            }
            plan.append((parts[0], combo, keyCode, offset))
        }

        try EventPoster.warmUp()
        // Modifiers are pressed 8 ms apart before the key-down: start each press that much earlier.
        let origin = ProbeClock.continuousMs() + 40
        var presses: [Press] = []
        for step in plan {
            let lead = Double(KeyCombo.Modifiers.pressOrder.filter { step.combo.modifiers.contains($0.modifier) }.count) * 8
            ProbeClock.sleep(untilContinuousMs: origin + step.offset - lead)
            let downAt = try EventPoster.press(step.combo, keyCode: step.keyCode, holdMs: holdMs)
            presses.append(Press(
                combo: step.text, keyCode: Int(step.keyCode), requestedOffsetMs: step.offset,
                keyDownContinuousMs: ProbeClock.rounded(downAt)))
        }
        try Console.json(presses)
    }
}
