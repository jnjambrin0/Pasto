import CoreGraphics
import Foundation
@testable import PastoCore
import Testing

/// What a plain red or plain blue icon is stored as: brightness capped at 0.96, then converted
/// from calibrated to device RGB.
enum StoredColorCode {
    static let vividRed = code(ofCalibrated: (0.96, 0, 0))
    static let vividBlue = code(ofCalibrated: (0, 0, 0.96))

    private static func code(ofCalibrated color: (red: Double, green: Double, blue: Double)) -> Int64 {
        let device = ApplicationColor.deviceComponents(ofCalibrated: color)
        return ColorCode.encode(red: device.red, green: device.green, blue: device.blue, alpha: 1)
    }
}

struct ApplicationColorTests {
    private typealias RGB = ApplicationColor.RGB

    private static let red: [UInt8] = [255, 0, 0, 255]
    private static let nearlyRed: [UInt8] = [254, 0, 0, 255]
    private static let blue: [UInt8] = [0, 0, 255, 255]
    private static let grey: [UInt8] = [128, 128, 128, 255]

    /// A one-row bitmap of these RGBA pixels.
    private func bitmap(_ pixels: [UInt8]...) -> RGBABitmap {
        RGBABitmap(width: pixels.count, height: 1, bytes: pixels.flatMap { $0 })
    }

    // MARK: - Dominant colour

    @Test func theMostFrequentColourWins() {
        let dominant = ApplicationColor.dominantColor(in: bitmap(Self.blue, Self.red, Self.red, Self.blue, Self.red))

        #expect(dominant == RGB(red: 255, green: 0, blue: 0))
    }

    @Test func translucentPixelsDoNotCount() {
        let almostOpaqueRed: [UInt8] = [255, 0, 0, 254]

        let dominant = ApplicationColor.dominantColor(in: bitmap(almostOpaqueRed, almostOpaqueRed, almostOpaqueRed, Self.blue))

        #expect(dominant == RGB(red: 0, green: 0, blue: 255))
    }

    @Test func dullPixelsDoNotCount() {
        // Saturation 0, 0, exactly 0.25 (not above it) and 0.255.
        let black: [UInt8] = [0, 0, 0, 255]
        let atTheThreshold: [UInt8] = [200, 150, 150, 255]
        let justAbove: [UInt8] = [200, 149, 149, 255]

        let dominant = ApplicationColor.dominantColor(
            in: bitmap(Self.grey, Self.grey, black, black, atTheThreshold, atTheThreshold, justAbove)
        )

        #expect(dominant == RGB(red: 200, green: 149, blue: 149))
    }

    @Test func coloursAreNotGrouped() {
        // Four reddish pixels of two exact tones lose to three pixels of one blue.
        let dominant = ApplicationColor.dominantColor(
            in: bitmap(Self.red, Self.red, Self.nearlyRed, Self.nearlyRed, Self.blue, Self.blue, Self.blue)
        )

        #expect(dominant == RGB(red: 0, green: 0, blue: 255))
    }

    @Test func aTieGoesToTheColourSeenFirst() {
        #expect(ApplicationColor.dominantColor(in: bitmap(Self.blue, Self.red, Self.red, Self.blue)) == RGB(red: 0, green: 0, blue: 255))
        #expect(ApplicationColor.dominantColor(in: bitmap(Self.red, Self.blue, Self.blue, Self.red)) == RGB(red: 255, green: 0, blue: 0))
    }

    @Test func anIconWithoutColourIsGrey() {
        #expect(ApplicationColor.dominantColor(in: bitmap(Self.grey, Self.grey)) == nil)
        #expect(ApplicationColor.code(for: bitmap(Self.grey, Self.grey)) == 0xFF7F_7F7F)
        #expect(ApplicationColor.code(for: nil) == 0xFF7F_7F7F)
    }

    // MARK: - Adjustment

    private func expectAdjusted(_ color: RGB, toBe expected: (Double, Double, Double), sourceLocation: SourceLocation = #_sourceLocation) {
        let adjusted = ApplicationColor.adjusted(color)
        #expect(abs(adjusted.red - expected.0) < 1e-9, sourceLocation: sourceLocation)
        #expect(abs(adjusted.green - expected.1) < 1e-9, sourceLocation: sourceLocation)
        #expect(abs(adjusted.blue - expected.2) < 1e-9, sourceLocation: sourceLocation)
    }

    @Test func brightColoursAreCappedBelowFullBrightness() {
        expectAdjusted(RGB(red: 255, green: 0, blue: 0), toBe: (0.96, 0, 0))
    }

    @Test func dimColoursAreBrightened() {
        // Brightness 0.6 → 0.75.
        expectAdjusted(RGB(red: 0, green: 153, blue: 0), toBe: (0, 0.75, 0))
    }

    @Test func darkColoursKeepTheirBrightness() {
        // Brightness 0.4 is still dark; saturation 0.5 is raised to 0.85.
        expectAdjusted(RGB(red: 102, green: 51, blue: 51), toBe: (0.4, 0.4 * 0.15, 0.4 * 0.15))
    }

    @Test func paleColoursAreSaturatedKeepingTheirHue() {
        // Hue 210°, saturation 0.5, brightness 0.8 → saturation 0.85.
        // At 210° green sits halfway between the weakest and the strongest component.
        expectAdjusted(RGB(red: 102, green: 153, blue: 204), toBe: (0.8 * 0.15, 0.8 * (1 - 0.85 / 2), 0.8))
    }

    @Test func aColourAlreadyVividIsLeftAlone() {
        // Saturation 0.9, brightness 0.8.
        expectAdjusted(RGB(red: 204, green: 0, blue: 0), toBe: (0.8, 0, 0))
        expectAdjusted(RGB(red: 20, green: 102, blue: 204), toBe: (20.0 / 255, 0.4, 0.8))
    }

    // MARK: - Stored code

    @Test func coloursAreStoredAsAARRGGBBWithTruncatedComponents() {
        #expect(ColorCode.encode(red: 0.5, green: 0.5, blue: 0.5, alpha: 1) == 0xFF7F_7F7F)
        #expect(ColorCode.encode(red: 1, green: 0, blue: 0.999, alpha: 1) == 0xFFFF_00FE)
        #expect(ColorCode.encode(red: 1.5, green: -0.2, blue: 0, alpha: 0) == 0x00FF_0000)
    }

    @Test func theCodeOfABitmapIsItsAdjustedDominantColourInDeviceRGB() {
        // Red at brightness 0.96, built as calibrated RGB and stored as device RGB.
        let device = ApplicationColor.deviceComponents(ofCalibrated: (0.96, 0, 0))
        let expected = ColorCode.encode(red: device.red, green: device.green, blue: device.blue, alpha: 1)
        #expect(ApplicationColor.code(for: bitmap(Self.red, Self.red, Self.blue)) == expected)
    }

    @Test func theConversionToDeviceRGBChangesTheComponents() {
        // Calibrated pure red is not pure red on the device: the stored colour moves.
        let device = ApplicationColor.deviceComponents(ofCalibrated: (0.96, 0, 0))
        #expect(device.green > 0)
        #expect(device.red > 0.96)
    }

    // MARK: - Icons

    @Test func anIconIsLookedAtAtOnePixelPerPoint() throws {
        let icon = TestImage.solid(.red, width: 256, height: 256)

        let bitmap = try #require(ApplicationIcon.colorBitmap(of: icon))

        #expect(bitmap.width == 128)
        #expect(bitmap.height == 128)
        #expect(bitmap.bytes.count == 128 * 128 * 4)
        #expect(ApplicationColor.dominantColor(in: bitmap) == RGB(red: 255, green: 0, blue: 0))
    }

    @Test func aSmallIconIsLookedAtAtItsOwnSize() throws {
        let bitmap = try #require(ApplicationIcon.colorBitmap(of: TestImage.solid(.red, width: 32, height: 16)))

        #expect(bitmap.width == 32)
        #expect(bitmap.height == 16)
    }

    @Test func theTransparentMarginOfAnIconIsIgnored() throws {
        // A blue square with a wide transparent margin, as icons have.
        let icon = TestImage.make(width: 128, height: 128) { x, y in
            (40..<88).contains(x) && (40..<88).contains(y) ? TestImage.Pixel(red: 0, green: 0, blue: 255) : .clear
        }

        #expect(ApplicationColor.code(for: ApplicationIcon.colorBitmap(of: icon)) == StoredColorCode.vividBlue)
    }
}

struct SourceApplicationResolverTests {
    private let icon = TestImage.solid(.red, width: 256, height: 256)
    private var safari: FrontmostApplication {
        FrontmostApplication(bundleIdentifier: "com.apple.Safari", name: "Safari", icon: icon)
    }

    @Test func aNewApplicationGetsItsIconAndItsColour() throws {
        let source = try #require(SourceApplicationResolver.sourceApplication(for: safari, stored: nil))

        #expect(source.bundleIdentifier == "com.apple.Safari")
        #expect(source.name == "Safari")
        #expect(source.colorCode == StoredColorCode.vividRed)
        let iconData = try #require(source.iconData)
        #expect(iconData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        // The pixels are stored as they were rendered.
        #expect(TestImage.pixelSize(of: iconData) == CGSize(width: 256, height: 256))
    }

    @Test func anApplicationNeedsIdentifierNameAndIcon() {
        var application = safari
        application.bundleIdentifier = nil
        #expect(SourceApplicationResolver.sourceApplication(for: application, stored: nil) == nil)

        application = safari
        application.name = nil
        #expect(SourceApplicationResolver.sourceApplication(for: application, stored: nil) == nil)

        application = safari
        application.icon = nil
        #expect(SourceApplicationResolver.sourceApplication(for: application, stored: nil) == nil)
    }

    @Test func theColourIsNotComputedAgainWhileTheIconIsTheSame() throws {
        let first = try #require(SourceApplicationResolver.sourceApplication(for: safari, stored: nil))
        // A colour the algorithm would never give this icon: if it comes back, nothing was recomputed.
        var stored = first
        stored.colorCode = 0xFF12_3456

        #expect(SourceApplicationResolver.sourceApplication(for: safari, stored: stored) == stored)
    }

    @Test func aNewIconBringsANewColour() throws {
        var stored = try #require(SourceApplicationResolver.sourceApplication(for: safari, stored: nil))
        stored.colorCode = 0xFF12_3456
        var updated = safari
        updated.icon = TestImage.solid(TestImage.Pixel(red: 0, green: 0, blue: 255), width: 256, height: 256)

        let source = try #require(SourceApplicationResolver.sourceApplication(for: updated, stored: stored))

        #expect(source.colorCode == StoredColorCode.vividBlue)
        #expect(source.iconData != stored.iconData)
    }

    @Test func aColourThatWasNeverComputedIsComputed() throws {
        var stored = try #require(SourceApplicationResolver.sourceApplication(for: safari, stored: nil))
        stored.colorCode = 0

        #expect(SourceApplicationResolver.sourceApplication(for: safari, stored: stored)?.colorCode == StoredColorCode.vividRed)
    }

    @Test func aStoredNameIsOnlyFilledInWhenEmpty() {
        var renamed = safari
        renamed.name = "Safari Technology Preview"

        let named = SourceApplication(bundleIdentifier: "com.apple.Safari", name: "Safari")
        #expect(SourceApplicationResolver.sourceApplication(for: renamed, stored: named)?.name == "Safari")

        let unnamed = SourceApplication(bundleIdentifier: "com.apple.Safari", name: "")
        #expect(SourceApplicationResolver.sourceApplication(for: renamed, stored: unnamed)?.name == "Safari Technology Preview")
    }
}
