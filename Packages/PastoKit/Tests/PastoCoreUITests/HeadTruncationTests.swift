import CoreGraphics
import Testing
@testable import PastoCoreUI

/// A file path that does not fit keeps its end.
@Suite struct HeadTruncationTests {
    @Test func capacityIsLinesTimesWholeCharactersPerLine() {
        #expect(HeadTruncation.capacity(lines: 2, width: 132, characterWidth: 3.65625) == 72)
        #expect(HeadTruncation.capacity(lines: 2, width: 212, characterWidth: 3.65625) == 114)
        #expect(HeadTruncation.capacity(lines: 1, width: 10, characterWidth: 3) == 3)
        #expect(HeadTruncation.capacity(lines: 2, width: 0, characterWidth: 3) == 0)
        #expect(HeadTruncation.capacity(lines: 2, width: 100, characterWidth: 0) == 0)
    }

    @Test func textThatFitsIsLeftAlone() {
        #expect(HeadTruncation.truncate("/tmp/a.txt", capacity: 10) == "/tmp/a.txt")
        #expect(HeadTruncation.truncate("/tmp/a.txt", capacity: 72) == "/tmp/a.txt")
        #expect(HeadTruncation.truncate("", capacity: 0) == "")
    }

    @Test func longTextKeepsItsEnd() {
        #expect(HeadTruncation.truncate("/Users/me/Documents/report.pdf", capacity: 10) == "…report.pdf")
        #expect(HeadTruncation.truncate("abcdef", capacity: 5) == "…bcdef")
        #expect(HeadTruncation.truncate("abcdef", capacity: 0) == "…")
    }

    /// An 89-character path on a 152 pt card keeps 72 characters.
    @Test func matchesTheReferenceCase() {
        let path = String(repeating: "x", count: 89)
        let capacity = HeadTruncation.capacity(lines: 2, width: 132, characterWidth: 3.65625)
        let shown = HeadTruncation.truncate(path, capacity: capacity)
        #expect(shown.count == 73)
        #expect(shown.hasPrefix("…"))
    }

    @Test func countsWholeCharacters() {
        #expect(HeadTruncation.truncate("carpeta/👩‍💻/日本語.txt", capacity: 8) == "…/日本語.txt")
    }
}
