import Testing
@testable import ProbeCore

@Suite struct ImageDiffTests {
    private let gray = RGBA(r: 100, g: 100, b: 100)

    @Test func identicalImagesHaveNoDifferences() throws {
        let image = Bitmap(width: 4, height: 3, fill: gray)
        let result = try ImageDiff.compare(image, image)
        #expect(result.differingPixels == 0)
        #expect(result.maxDelta == 0)
        #expect(result.meanDelta == 0)
        #expect(result.boundingBox == nil)
    }

    @Test func reportsCountMeanMaxAndBoundingBox() throws {
        let a = Bitmap(width: 4, height: 4, fill: gray)
        var b = a
        b[1, 1] = RGBA(r: 110, g: 100, b: 100) // delta 10
        b[2, 3] = RGBA(r: 100, g: 60, b: 130) // delta 40, largest channel wins
        let result = try ImageDiff.compare(a, b)
        #expect(result.differingPixels == 2)
        #expect(result.differingPercent == 12.5)
        #expect(result.maxDelta == 40)
        #expect(result.meanDelta == 50.0 / 16.0)
        #expect(result.boundingBox == .init(x: 1, y: 1, w: 2, h: 3))
    }

    @Test func deltaEqualToThresholdDoesNotCount() throws {
        let a = Bitmap(width: 2, height: 1, fill: gray)
        var b = a
        b[0, 0] = RGBA(r: 102, g: 100, b: 100)
        b[1, 0] = RGBA(r: 103, g: 100, b: 100)
        #expect(try ImageDiff.compare(a, b, threshold: 2).differingPixels == 1)
        #expect(try ImageDiff.compare(a, b, threshold: 0).differingPixels == 2)
    }

    @Test func alphaChannelTakesPartInTheDelta() throws {
        let a = Bitmap(width: 1, height: 1, fill: RGBA(r: 0, g: 0, b: 0, a: 255))
        let b = Bitmap(width: 1, height: 1, fill: RGBA(r: 0, g: 0, b: 0, a: 0))
        #expect(try ImageDiff.compare(a, b).maxDelta == 255)
    }

    @Test func differentSizesNeedCropCommon() throws {
        let a = Bitmap(width: 4, height: 2, fill: gray)
        var b = Bitmap(width: 3, height: 5, fill: gray)
        b[2, 1] = RGBA(r: 0, g: 0, b: 0)
        #expect(throws: ProbeError.self) { try ImageDiff.compare(a, b) }

        let result = try ImageDiff.compare(a, b, cropCommon: true)
        #expect(result.compared == .init(width: 3, height: 2))
        #expect(result.differingPixels == 1)
        #expect(result.boundingBox == .init(x: 2, y: 1, w: 1, h: 1))
    }

    @Test func heatmapDimsMatchesAndReddensDifferences() throws {
        let a = Bitmap(width: 2, height: 1, fill: RGBA(r: 90, g: 90, b: 90))
        var b = a
        b[1, 0] = RGBA(r: 90, g: 90, b: 255)
        let (result, heatmap) = try ImageDiff.compareWithHeatmap(a, b)
        #expect(result.differingPixels == 1)
        #expect(heatmap[0, 0] == RGBA(r: 30, g: 30, b: 30)) // luma 90 dimmed to a third
        #expect(heatmap[1, 0] == RGBA(r: UInt8(96 + 165 * 159 / 255), g: 0, b: 0))
    }
}

@Suite struct BitmapTests {
    @Test func averagesABlockClippedToTheImage() throws {
        var image = Bitmap(width: 3, height: 3, fill: RGBA(r: 0, g: 0, b: 0))
        image[2, 2] = RGBA(r: 200, g: 100, b: 40)

        let single = try #require(image.average(centerX: 2, centerY: 2, size: 1))
        #expect(single.color == RGBA(r: 200, g: 100, b: 40))
        #expect(single.samples == 1)

        // A 3x3 block centred on the corner only covers the 2x2 pixels inside the image.
        let corner = try #require(image.average(centerX: 2, centerY: 2, size: 3))
        #expect(corner.samples == 4)
        #expect(corner.color == RGBA(r: 50, g: 25, b: 10))

        #expect(image.average(centerX: 3, centerY: 0, size: 1) == nil)
    }

    @Test func unpremultipliesTranslucentPixels() {
        #expect(RGBA(r: 64, g: 32, b: 0, a: 128).unpremultiplied == RGBA(r: 128, g: 64, b: 0, a: 128))
        #expect(RGBA(r: 10, g: 20, b: 30, a: 255).unpremultiplied == RGBA(r: 10, g: 20, b: 30, a: 255))
        #expect(RGBA(r: 255, g: 149, b: 0).hex == "#FF9500")
    }

    @Test func rejectsBuffersOfTheWrongSize() {
        #expect(throws: ProbeError.self) { try Bitmap(width: 2, height: 2, pixels: [0, 0, 0, 0]) }
    }
}
