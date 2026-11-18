import Foundation
import Testing
@testable import PastoPreview

/// What the footers say.
@Suite struct FooterContentTests {
    // MARK: Colour notations

    @Test func aPrimaryColour() {
        let red = ColorFormats(red: 1, green: 0, blue: 0)
        // A full channel reads 256: the components are scaled by 256.
        #expect(red.rgb == [256, 0, 0])
        #expect(red.hsl == [0, 100, 50])
        #expect(red.hsb == [0, 100, 100])
    }

    @Test func greys() {
        #expect(ColorFormats(red: 1, green: 1, blue: 1).hsl == [0, 0, 100])
        #expect(ColorFormats(red: 1, green: 1, blue: 1).hsb == [0, 0, 100])
        #expect(ColorFormats(red: 0, green: 0, blue: 0).rgb == [0, 0, 0])
        #expect(ColorFormats(red: 0, green: 0, blue: 0).hsl == [0, 0, 0])
        #expect(ColorFormats(red: 0.5, green: 0.5, blue: 0.5).hsb == [0, 0, 50])
    }

    @Test func aMixedColour() {
        let color = ColorFormats(red: 0.25, green: 0.5, blue: 0.75)
        #expect(color.rgb == [64, 128, 192])
        #expect(color.hsl == [210, 50, 50])
        // Saturation is 66.67 %: this notation is cut, not rounded.
        #expect(color.hsb == [210, 66, 75])
    }

    @Test func halvesRoundAwayFromZero() {
        // 0.125 × 100 and 12.5 / 256 × 256 are both exactly 12.5.
        #expect(ColorFormats(red: 0.125, green: 0.125, blue: 0.125).hsl == [0, 0, 13])
        #expect(ColorFormats(red: 12.5 / 256, green: 0, blue: 0).rgb == [13, 0, 0])
    }

    @Test func huesWrapAroundTheWheel() {
        #expect(ColorFormats(red: 1, green: 0, blue: 0.5).hsb[0] == 330)
        #expect(ColorFormats(red: 0, green: 1, blue: 0).hsb[0] == 120)
        #expect(ColorFormats(red: 0, green: 0, blue: 1).hsb[0] == 240)
    }

    @Test func notationsAreNamedAndCommaSeparated() {
        let entries = ColorFormats(red: 0.25, green: 0.5, blue: 0.75).entries
        #expect(entries.map(\.name) == ["RGB", "HSL", "HSB"])
        #expect(entries.map(\.value) == ["64, 128, 192", "210, 50, 50", "210, 66, 75"])
    }

    // MARK: Files caption

    @Test func aSingleFileShowsItsPath() {
        #expect(FilesCaption.text(paths: ["/tmp/a.txt"], totalByteCount: nil, multipleFilesTitle: "Several") == "/tmp/a.txt")
    }

    @Test func anyOtherNumberOfFilesShowsTheSharedTitle() {
        #expect(FilesCaption.text(paths: ["/a", "/b"], totalByteCount: nil, multipleFilesTitle: "Several") == "Several")
        #expect(FilesCaption.text(paths: [], totalByteCount: nil, multipleFilesTitle: "Several") == "Several")
    }

    @Test func aKnownSizeFollowsAfterADot() {
        let caption = FilesCaption.text(paths: ["/tmp/a.txt"], totalByteCount: 2_000_000, multipleFilesTitle: "Several")
        #expect(caption.hasPrefix("/tmp/a.txt  ·  "))
        #expect(caption.count > "/tmp/a.txt  ·  ".count)
    }

    @Test func anEmptySizeIsLeftOut() {
        #expect(FilesCaption.text(paths: ["/tmp/a.txt"], totalByteCount: 0, multipleFilesTitle: "Several") == "/tmp/a.txt")
    }

    // MARK: Strings

    /// A key that is missing from the catalog comes back as itself.
    @Test func theCatalogHasTheCountedStrings() {
        for caption in [PreviewStrings.characterCount(2), PreviewStrings.wordCount(2), PreviewStrings.lineCount(2)] {
            #expect(caption.contains("2"))
            #expect(!caption.contains("statistics."))
        }
        #expect(PreviewStrings.openIn("Safari").contains("Safari"))
    }
}
