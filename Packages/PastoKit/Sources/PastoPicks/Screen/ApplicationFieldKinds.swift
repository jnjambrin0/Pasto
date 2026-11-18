/// The field kind of applications whose purpose says it, for when the destination window was
/// not looked at or told nothing.
///
/// A short list of widely used applications, matched by bundle identifier prefix; the first entry
/// that matches decides.
enum ApplicationFieldKinds {
    static func fieldKind(ofApplication bundleIdentifier: String) -> FieldKind? {
        entries.first { bundleIdentifier.hasPrefix($0.prefix) }?.kind
    }

    private static let entries: [(prefix: String, kind: FieldKind)] = [
        // Terminals
        ("com.apple.Terminal", .terminal),
        ("com.googlecode.iterm2", .terminal),
        ("dev.warp.Warp", .terminal),
        ("com.mitchellh.ghostty", .terminal),
        ("net.kovidgoyal.kitty", .terminal),
        ("org.alacritty", .terminal),
        // Code editors and development environments
        ("com.apple.dt.Xcode", .code),
        ("com.microsoft.VSCode", .code),
        ("com.jetbrains.", .code),
        ("com.sublimetext.", .code),
        ("dev.zed.Zed", .code),
        ("com.panic.Nova", .code),
        ("com.barebones.bbedit", .code),
        // Spreadsheets
        ("com.apple.iWork.Numbers", .cell),
        ("com.microsoft.Excel", .cell),
        // Design tools
        ("com.figma.Desktop", .canvas),
        ("com.bohemiancoding.sketch3", .canvas),
        // Freeform's identifier is all lowercase; prefixes are matched case-sensitively.
        ("com.apple.freeform", .canvas),
        // Messaging and assistants
        ("com.apple.MobileSMS", .chat),
        ("com.tinyspeck.slackmacgap", .chat),
        ("com.hnc.Discord", .chat),
        ("ru.keepcoder.Telegram", .chat),
        ("net.whatsapp.WhatsApp", .chat),
        ("com.microsoft.teams", .chat),
        ("com.openai.chat", .chat),
        ("com.anthropic.claudefordesktop", .chat),
    ]
}
