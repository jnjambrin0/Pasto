/// How a colour is stored in `ApplicationEntity.rawColor`: `0xAARRGGBB`.
enum ColorCode {
    /// Components are clamped to 0…1 and scaled to a byte by truncation, not rounding: a mid grey
    /// of 0.5 is stored as `7F`.
    static func encode(red: Double, green: Double, blue: Double, alpha: Double) -> Int64 {
        Int64(byte(alpha)) << 24 | Int64(byte(red)) << 16 | Int64(byte(green)) << 8 | Int64(byte(blue))
    }

    private static func byte(_ component: Double) -> UInt8 {
        component <= 0 ? 0 : UInt8(min(component, 1) * 255)
    }
}
