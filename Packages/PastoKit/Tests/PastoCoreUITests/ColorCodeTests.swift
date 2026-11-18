import Testing
@testable import PastoCoreUI

/// A stored colour: its components, its hex text and whether a label on it is drawn dark.
@Suite struct ColorCodeTests {
    @Test func hexStringIsAlwaysHashAndSixUppercaseDigits() {
        #expect(ColorCode(rawValue: 0x34C759).hexString == "#34C759")
        #expect(ColorCode(rawValue: 0x00000A).hexString == "#00000A")
        #expect(ColorCode(rawValue: 0xABCDEF).hexString == "#ABCDEF")
        // The alpha byte is not part of the text.
        #expect(ColorCode(rawValue: 0x80FF_9500).hexString == "#FF9500")
        #expect(ColorCode(truncating: UInt64(0x1_00FF_9500)).hexString == "#FF9500")
    }

    @Test func componentsComeFromTheirBytes() {
        let color = ColorCode(rawValue: 0x80FF_3300)
        #expect(color.red == 1)
        #expect(color.green == 0.2)
        #expect(color.blue == 0)
        #expect(abs(color.alpha - 128.0 / 255) < 1e-9)
    }

    @Test func zeroAlphaByteMeansOpaque() {
        #expect(ColorCode(rawValue: 0x0088FF).alpha == 1)
        #expect(ColorCode(rawValue: 0xFF00_88FF).alpha == 1)
        #expect(ColorCode(truncating: Int64(4_278_225_151)) == ColorCode(rawValue: 0xFF00_88FF))
    }

    @Test func componentsAreRoundedAndClamped() {
        #expect(ColorCode(red: 0.5, green: 0.5, blue: 0.5).rawValue == 0xFF80_8080)
        #expect(ColorCode(red: 0.999, green: 0.001, blue: 0.2).rawValue == 0xFFFF_0033)
        #expect(ColorCode(red: 2, green: -1, blue: 1, alpha: 1).rawValue == 0xFFFF_00FF)
    }

    /// The label on a colour card is dark when the weighted luma of the colour exceeds 0.55.
    @Test func lightColorsGetDarkText() {
        #expect(ColorCode(rawValue: 0x34C759).isLight)      // luma 0.559
        #expect(ColorCode(rawValue: 0xFF9500).isLight)      // luma 0.642
        #expect(ColorCode(rawValue: 0xF5F5F7).isLight)
        #expect(!ColorCode(rawValue: 0x102040).isLight)     // luma 0.121
        #expect(ColorCode(rawValue: 0xFFFFFF).isLight)
        #expect(!ColorCode(rawValue: 0x000000).isLight)
    }

    @Test func lumaThresholdIsExclusive() {
        // Grays have a luma equal to their level: 140 / 255 = 0.549, 141 / 255 = 0.553.
        #expect(!ColorCode(rawValue: 0x8C8C8C).isLight)
        #expect(ColorCode(rawValue: 0x8D8D8D).isLight)
        // Pure colours show the weights: green alone passes, red and blue alone do not.
        #expect(ColorCode(rawValue: 0x00FF00).isLight)
        #expect(!ColorCode(rawValue: 0xFF0000).isLight)
        #expect(!ColorCode(rawValue: 0x0000FF).isLight)
    }

    @Test func alphaDoesNotAffectLightness() {
        #expect(ColorCode(rawValue: 0x10FF_FFFF).isLight)
    }
}
