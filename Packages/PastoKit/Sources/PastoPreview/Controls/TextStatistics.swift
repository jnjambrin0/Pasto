import Foundation

/// The counts under a text.
nonisolated struct TextStatistics: Equatable {
    /// User-perceived characters.
    let characters: Int
    /// Runs of anything between spaces and tabs; a line break alone does not separate words.
    let words: Int
    /// One more than the line breaks, so an empty text has one line.
    let lines: Int

    init(of text: String) {
        characters = text.count
        words = text.components(separatedBy: .whitespaces).count { !$0.isEmpty }
        lines = text.components(separatedBy: .newlines).count
    }
}
