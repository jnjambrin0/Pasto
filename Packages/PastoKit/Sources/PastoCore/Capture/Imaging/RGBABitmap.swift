import CoreGraphics

/// Pixels as rows of RGBA bytes, alpha last: what the icon colour and the transparency test look at.
struct RGBABitmap: Sendable {
    let width: Int
    let height: Int
    /// `width * height * 4` bytes, top row first.
    let bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// `image` stretched over `width` × `height` pixels in device RGB, 8 bits per sample.
    ///
    /// Alpha is premultiplied, which leaves fully opaque pixels — the only ones whose colour is
    /// looked at — exactly as they are.
    init?(drawing image: CGImage, width: Int, height: Int) {
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        let byteCount = width * height * 4
        self.init(
            width: width,
            height: height,
            bytes: Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: byteCount))
        )
    }
}
