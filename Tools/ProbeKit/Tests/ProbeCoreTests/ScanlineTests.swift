import Testing
@testable import ProbeCore

@Suite struct ScanlineTests {
    private let dark = RGBA(r: 20, g: 20, b: 20)
    private let light = RGBA(r: 200, g: 200, b: 200)

    @Test func splitsARowIntoRuns() throws {
        var image = Bitmap(width: 6, height: 2, fill: dark)
        image[2, 1] = light
        image[3, 1] = light
        let (offset, pixels) = try Scanline.pixels(of: image, along: .row(1))
        let runs = Scanline.runs(pixels, offset: offset)
        #expect(runs.map(\.start) == [0, 2, 4])
        #expect(runs.map(\.end) == [1, 3, 5])
        #expect(runs.map(\.hex) == ["#141414", "#C8C8C8", "#141414"])
    }

    @Test func columnsAndRangesUseImageCoordinates() throws {
        var image = Bitmap(width: 2, height: 8, fill: dark)
        image[1, 5] = light
        let (offset, pixels) = try Scanline.pixels(of: image, along: .column(1), range: 3..<8)
        let runs = Scanline.runs(pixels, offset: offset)
        #expect(runs.map(\.start) == [3, 5, 6])
        #expect(runs.map(\.length) == [2, 1, 2])
    }

    @Test func toleranceIsMeasuredAgainstTheFirstPixelOfTheRun() {
        let pixels = [20, 22, 24, 26].map { RGBA(r: $0, g: 20, b: 20) }
        #expect(Scanline.runs(pixels, tolerance: 4).map(\.length) == [3, 1])
        #expect(Scanline.runs(pixels, tolerance: 6).map(\.length) == [4])
    }

    @Test func shortRunsMergeIntoOneColourlessStretch() {
        let pixels = [dark, dark, dark, light, dark, light, dark, dark, dark]
        let runs = Scanline.runs(pixels, offset: 10, minRun: 3)
        #expect(runs.map(\.start) == [10, 13, 16])
        #expect(runs[1].hex == nil)
        #expect(runs[1].pieces == 3)
        #expect(runs[1].length == 3)
    }

    @Test func differenceReportsFirstLastAndCount() {
        let a = [dark, dark, dark, dark, dark]
        let b = [dark, light, dark, light, dark]
        #expect(Scanline.difference(a, b, offset: 100) == .init(first: 101, last: 103, count: 2))
        #expect(Scanline.difference(a, a) == nil)
    }

    @Test func linesOutsideTheImageAreRejected() {
        let image = Bitmap(width: 2, height: 2, fill: dark)
        #expect(throws: ProbeError.self) { try Scanline.pixels(of: image, along: .row(2)) }
        #expect(throws: ProbeError.self) { try Scanline.pixels(of: image, along: .column(0), range: 5..<9) }
    }
}
