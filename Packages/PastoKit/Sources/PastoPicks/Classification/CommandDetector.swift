/// Whether a text reads as a terminal command: a single line without sentence punctuation that
/// starts with a common command-line tool or a relative path, or that pipes or chains commands.
enum CommandDetector {
    static func isCommand(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline), !sentencePunctuation.matches(text) else { return false }
        return startsWithTool(text) || text.contains(" | ") || text.contains(" && ")
    }

    /// A question or an exclamation mark, or a full stop that ends a sentence.
    private static let sentencePunctuation = TextPattern(#"[?!]|\.\s"#, scope: .anywhere)

    /// The tools whose name followed by a space starts a command; the name alone does not.
    private static let tools = [
        "git", "brew", "npm", "npx", "yarn", "pip", "pip3", "sudo", "cd", "ls", "curl", "ssh",
        "docker", "kubectl", "make", "swift", "python3", "node",
    ]
    /// Prefixes that start a command by themselves: running something from here or from home.
    private static let pathPrefixes = ["./", "~/"]

    private static func startsWithTool(_ text: String) -> Bool {
        pathPrefixes.contains(where: text.hasPrefix) || tools.contains { text.hasPrefix($0 + " ") }
    }
}
