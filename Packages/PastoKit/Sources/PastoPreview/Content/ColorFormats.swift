import Foundation

/// The three notations under a colour.
nonisolated struct ColorFormats: Equatable {
    let rgb: [Int]
    let hsl: [Int]
    let hsb: [Int]

    /// Components in 0...1.
    init(red: Double, green: Double, blue: Double) {
        let highest = max(red, green, blue)
        let delta = highest - min(red, green, blue)

        // In degrees from the start: sixths of a turn are exact, thirds of one are not.
        var hue = 0.0
        if delta > 0 {
            let sector = switch highest {
            case red: (green - blue) / delta
            case green: (blue - red) / delta + 2
            default: (red - green) / delta + 4
            }
            hue = 60 * (sector < 0 ? sector + 6 : sector)
        }
        let saturation = highest > 0 ? delta / highest : 0
        let brightness = highest

        let lightness = (2 - saturation) * brightness / 2
        let lightnessRoom = min(lightness, 1 - lightness)
        let hslSaturation = lightnessRoom > 0 ? (brightness - lightness) / lightnessRoom : 0

        // Halves go away from zero: 12.5 reads 13.
        func rounded(_ value: Double) -> Int { Int(value.rounded(.toNearestOrAwayFromZero)) }
        rgb = [red, green, blue].map { rounded($0 * PreviewMetrics.rgbComponentScale) }
        hsl = [rounded(hue), rounded(hslSaturation * 100), rounded(lightness * 100)]
        // Truncated, not rounded, unlike the other two.
        hsb = [Int(hue), Int(saturation * 100), Int(brightness * 100)]
    }

    /// Name and value of each notation, in the order they are shown.
    var entries: [(name: String, value: String)] {
        [("RGB", rgb), ("HSL", hsl), ("HSB", hsb)].map { name, components in
            (name, components.map(String.init).joined(separator: ", "))
        }
    }
}
