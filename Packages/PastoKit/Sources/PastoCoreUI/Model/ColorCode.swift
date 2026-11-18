import Foundation

/// A colour as the store keeps it: `0xAARRGGBB`, where a zero alpha byte means opaque. Colour
/// items and source applications both use it.
public nonisolated struct ColorCode: Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Keeps the low 32 bits, which is all the encoding uses.
    public init(truncating value: Int64) {
        rawValue = UInt32(truncatingIfNeeded: value)
    }

    public init(truncating value: UInt64) {
        rawValue = UInt32(truncatingIfNeeded: value)
    }

    /// Components in 0...1, rounded to the nearest of the 256 levels a byte can hold. Values
    /// outside that range are clamped.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func byte(_ component: Double) -> UInt32 {
            UInt32((min(max(component, 0), 1) * 255).rounded())
        }
        rawValue = byte(alpha) << 24 | byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    public var red: Double { Double((rawValue >> 16) & 0xFF) / 255 }
    public var green: Double { Double((rawValue >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(rawValue & 0xFF) / 255 }

    public var alpha: Double {
        let byte = rawValue >> 24
        return byte == 0 ? 1 : Double(byte) / 255
    }

    /// Whether dark text reads better on this colour than light text. Alpha plays no part.
    public var isLight: Bool {
        Self.isLight(red: red, green: green, blue: blue)
    }

    /// `#RRGGBB`: always with the hash, six uppercase digits, no alpha.
    public var hexString: String {
        String(format: "#%06X", rawValue & 0xFFFFFF)
    }

    static let lightnessThreshold = 0.55

    static func isLight(red: Double, green: Double, blue: Double) -> Bool {
        0.299 * red + 0.587 * green + 0.114 * blue > lightnessThreshold
    }
}
