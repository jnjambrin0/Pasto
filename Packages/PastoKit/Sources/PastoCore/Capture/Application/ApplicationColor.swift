import AppKit

/// The colour that stands for an application: the most frequent exact colour among the opaque,
/// colourful pixels of its icon, pushed towards a vivid tone.
///
/// Pasto has no per-application table of fixed colours: every colour comes from here.
enum ApplicationColor {
    /// `NSColor.gray` as it is stored: what an icon without a usable colour gets.
    static let fallbackCode: Int64 = 0xFF7F_7F7F

    /// A pixel counts only above this saturation (and only if fully opaque).
    private static let minimumPixelSaturation = 0.25
    /// The chosen colour is made at least this saturated.
    private static let minimumSaturation = 0.85
    /// Up to this brightness a colour is dark on purpose and keeps its brightness…
    private static let darkBrightness = 0.4
    /// …above it, brightness is brought into this range.
    private static let brightnessRange = 0.75...0.96

    struct RGB: Equatable, Sendable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }

    /// The stored colour code for an icon rendered as `bitmap`; grey when there is no bitmap or
    /// no pixel of it counts (grey, black-and-white or translucent icons).
    static func code(for bitmap: RGBABitmap?) -> Int64 {
        guard let bitmap, let dominant = dominantColor(in: bitmap) else { return fallbackCode }
        let color = deviceComponents(ofCalibrated: adjusted(dominant))
        return ColorCode.encode(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    /// The adjusted colour is built in calibrated RGB and stored converted to device RGB, which
    /// changes the components: iTerm2's icon gives `#130014` read as device values and `#180119`
    /// once converted, which is what is stored.
    static func deviceComponents(
        ofCalibrated color: (red: Double, green: Double, blue: Double)
    ) -> (red: Double, green: Double, blue: Double) {
        let calibrated = NSColor(calibratedRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        guard let device = calibrated.usingColorSpace(.deviceRGB) else { return color }
        return (Double(device.redComponent), Double(device.greenComponent), Double(device.blueComponent))
    }

    /// The exact colour most pixels have. Every pixel is looked at and colours are not grouped:
    /// two tones one level apart are two colours, so a flat area beats a larger soft gradient.
    ///
    /// Colours with the same count resolve to the one that appears first, top row first, so the
    /// result never depends on the order of a hash table.
    static func dominantColor(in bitmap: RGBABitmap) -> RGB? {
        var tallies: [UInt32: (count: Int, firstOffset: Int)] = [:]
        for offset in stride(from: 0, to: bitmap.bytes.count - 3, by: 4) {
            let red = bitmap.bytes[offset]
            let green = bitmap.bytes[offset + 1]
            let blue = bitmap.bytes[offset + 2]
            guard bitmap.bytes[offset + 3] == .max else { continue }

            let strongest = max(red, green, blue)
            let weakest = min(red, green, blue)
            guard strongest > 0,
                  Double(strongest - weakest) / Double(strongest) > minimumPixelSaturation
            else { continue }

            let key = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
            tallies[key, default: (0, offset)].count += 1
        }

        let winner = tallies.max { first, second in
            if first.value.count != second.value.count {
                return first.value.count < second.value.count
            }
            return first.value.firstOffset > second.value.firstOffset
        }
        return winner.map { RGB(red: UInt8($0.key >> 16 & 0xFF), green: UInt8($0.key >> 8 & 0xFF), blue: UInt8($0.key & 0xFF)) }
    }

    /// Same hue; saturation raised to the minimum; brightness brought into range unless the
    /// colour is dark. The result is meant as calibrated RGB (`deviceComponents(ofCalibrated:)`).
    static func adjusted(_ color: RGB) -> (red: Double, green: Double, blue: Double) {
        let red = Double(color.red) / 255
        let green = Double(color.green) / 255
        let blue = Double(color.blue) / 255

        let brightness = max(red, green, blue)
        let chroma = brightness - min(red, green, blue)
        let saturation = brightness == 0 ? 0 : chroma / brightness
        // In sixths of the colour wheel.
        var hue: Double
        if chroma == 0 {
            hue = 0
        } else if brightness == red {
            hue = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
        } else if brightness == green {
            hue = (blue - red) / chroma + 2
        } else {
            hue = (red - green) / chroma + 4
        }
        if hue < 0 {
            hue += 6
        }

        let newSaturation = max(saturation, minimumSaturation)
        let newBrightness = brightness <= darkBrightness
            ? brightness
            : min(max(brightness, brightnessRange.lowerBound), brightnessRange.upperBound)
        return rgb(hue: hue, saturation: newSaturation, brightness: newBrightness)
    }

    /// - Parameter hue: In sixths of the colour wheel, 0 ≤ hue < 6.
    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> (red: Double, green: Double, blue: Double) {
        let sector = Int(hue) % 6
        let fraction = hue - hue.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        switch sector {
        case 0: return (brightness, rising, low)
        case 1: return (falling, brightness, low)
        case 2: return (low, brightness, rising)
        case 3: return (low, falling, brightness)
        case 4: return (rising, low, brightness)
        default: return (brightness, low, falling)
        }
    }
}
