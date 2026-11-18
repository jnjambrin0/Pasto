import Testing
@testable import ProbeCore

@Suite struct FrameTraceTests {
    private let white = RGBA(r: 255, g: 255, b: 255)
    private let dark = RGBA(r: 32, g: 32, b: 32)

    @Test func edgeFindsTheFirstPixelUnlikeTheBackground() throws {
        var image = Bitmap(width: 1, height: 10, fill: white)
        for y in 6..<10 { image[0, y] = dark }
        let edge = FrameTrace.Edge(axis: .column(0), range: 0..<10, background: white, tolerance: 8, fromEnd: false)
        #expect(try FrameTrace.edge(edge, in: image) == 6)
        let backwards = FrameTrace.Edge(axis: .column(0), range: 0..<10, background: dark, tolerance: 8, fromEnd: true)
        #expect(try FrameTrace.edge(backwards, in: image) == 5)
    }

    @Test func progressIsTheBlendCoefficientOfACrossFade() {
        let start = Bitmap(width: 2, height: 2, fill: dark)
        let end = Bitmap(width: 2, height: 2, fill: white)
        let quarter = Bitmap(width: 2, height: 2, fill: RGBA(r: 88, g: 88, b: 88))
        let value = FrameTrace.progress(quarter, start: start, end: end, rect: (0, 0, 2, 2))
        #expect(value.map { abs($0 - 0.2511) < 0.001 } == true)
        #expect(FrameTrace.progress(quarter, start: start, end: start, rect: (0, 0, 2, 2)) == nil)
    }
}
