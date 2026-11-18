import Testing
@testable import ProbeCore

@Suite struct ColorCensusTests {
    @Test func countsTopColoursAndExtremes() throws {
        var image = Bitmap(width: 4, height: 4, fill: RGBA(r: 30, g: 30, b: 30))
        image[1, 1] = RGBA(r: 250, g: 250, b: 250)
        image[2, 1] = RGBA(r: 250, g: 250, b: 250)
        image[3, 3] = RGBA(r: 0, g: 0, b: 0)
        let result = try ColorCensus.census(of: image, x: 0, y: 0, width: 4, height: 4, top: 2)
        #expect(result.pixels == 16)
        #expect(result.distinct == 3)
        #expect(result.top.map(\.hex) == ["#1E1E1E", "#FAFAFA"])
        #expect(result.top.map(\.count) == [13, 2])
        #expect(result.brightest.hex == "#FAFAFA")
        #expect(result.darkest.hex == "#000000")
    }

    @Test func clipsTheRectangleToTheImage() throws {
        let image = Bitmap(width: 3, height: 3, fill: RGBA(r: 9, g: 9, b: 9))
        #expect(try ColorCensus.census(of: image, x: 2, y: 2, width: 10, height: 10).pixels == 1)
        #expect(throws: ProbeError.self) { try ColorCensus.census(of: image, x: 5, y: 0, width: 2, height: 2) }
    }
}
