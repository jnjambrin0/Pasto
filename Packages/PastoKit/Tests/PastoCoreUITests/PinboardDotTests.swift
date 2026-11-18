import AppKit
import Testing
@testable import PastoCoreUI

/// A pinboard's dot: a disc in the pinboard's colour ringed by a darker shade of it.
@Suite struct PinboardDotTests {
    @Test func theRingIsTheColourDarkenedByAFifth() throws {
        let yellow = NSColor(srgbRed: 242 / 255, green: 182 / 255, blue: 0, alpha: 1)

        let ring = try #require(PinboardDot.ringColor(of: yellow).usingColorSpace(.sRGB))

        #expect(abs(ring.redComponent - 0.8 * 242 / 255) < 0.001)
        #expect(abs(ring.greenComponent - 0.8 * 182 / 255) < 0.001)
        #expect(ring.blueComponent == 0)
        #expect(ring.alphaComponent == 1)
    }

    @Test func theImageIsAsLargeAsAsked() {
        #expect(PinboardDot.image(color: .systemBlue, side: 12).size == NSSize(width: 12, height: 12))
    }
}
