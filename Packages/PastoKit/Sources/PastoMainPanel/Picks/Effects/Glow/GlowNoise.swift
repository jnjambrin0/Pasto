import simd

/// The volume of noise the glow's flames are drawn from: smooth value noise that tiles in all
/// three directions, so it can drift forever, stored one byte per sample.
///
/// The lattice values come from a small integer hash: any periodic noise with these frequencies
/// and this normalisation gives the same look.
nonisolated enum GlowNoise {
    static let width = 80
    static let height = 80
    static let depth = 40
    static var sampleCount: Int { width * height * depth }

    /// One layer of noise: lattice cells per side of the volume, and the seed of its values.
    struct Octave {
        var period: SIMD3<Int32>
        var seed: UInt32
        var weight: Float
    }

    static let octaves = [
        Octave(period: SIMD3(3, 3, 6), seed: 1, weight: 1),
        Octave(period: SIMD3(6, 6, 12), seed: 2, weight: 0.5),
    ]

    /// How many standard deviations a byte step is: the noise is centred on 0.5 and spread so
    /// that one deviation spans 0.15.
    static let spread: Float = 0.15

    /// Every sample, x fastest, then y, then z. Takes a moment: call it off the main actor.
    @concurrent static func makeSamples() async -> [UInt8] {
        samples()
    }

    static func samples() -> [UInt8] {
        var values = [Float]()
        values.reserveCapacity(sampleCount)
        for z in 0..<depth {
            for y in 0..<height {
                for x in 0..<width {
                    let point = SIMD3(Float(x) / Float(width), Float(y) / Float(height), Float(z) / Float(depth))
                    values.append(octaves.reduce(0) { $0 + $1.weight * value(at: point, octave: $1) })
                }
            }
        }
        return normalised(values)
    }

    /// Centres the values on their mean and scales them by their deviation, as bytes.
    static func normalised(_ values: [Float]) -> [UInt8] {
        guard !values.isEmpty else { return [] }
        let count = Float(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
        let deviation = max(variance.squareRoot(), .ulpOfOne)
        return values.map { value in
            let level = ((value - mean) / deviation * spread + 0.5) * 255
            return UInt8(min(max(level, 0), 255).rounded())
        }
    }

    /// Value noise at `point` (each coordinate in 0..<1): the lattice values around it blended
    /// with smoothstep weights, the lattice wrapping at the octave's period.
    static func value(at point: SIMD3<Float>, octave: Octave) -> Float {
        let scaled = point * SIMD3<Float>(octave.period)
        let cell = SIMD3<Int32>(scaled.rounded(.down))
        let fraction = scaled - SIMD3<Float>(cell)
        let weight = fraction * fraction * (3 - 2 * fraction)

        func lattice(_ dx: Int32, _ dy: Int32, _ dz: Int32) -> Float {
            // The point is inside the volume, so only the far corners can need wrapping.
            let corner = (cell &+ SIMD3(dx, dy, dz)) % octave.period
            return hash(corner, seed: octave.seed)
        }
        func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

        let x00 = mix(lattice(0, 0, 0), lattice(1, 0, 0), weight.x)
        let x10 = mix(lattice(0, 1, 0), lattice(1, 1, 0), weight.x)
        let x01 = mix(lattice(0, 0, 1), lattice(1, 0, 1), weight.x)
        let x11 = mix(lattice(0, 1, 1), lattice(1, 1, 1), weight.x)
        return mix(mix(x00, x10, weight.y), mix(x01, x11, weight.y), weight.z)
    }

    /// A value in 0..<1 for a lattice point.
    static func hash(_ point: SIMD3<Int32>, seed: UInt32) -> Float {
        var h = UInt32(bitPattern: point.x) &* 0x8DA6_B343
        h ^= UInt32(bitPattern: point.y) &* 0xD816_3841
        h ^= UInt32(bitPattern: point.z) &* 0xCB1A_B31F
        h ^= seed &* 0x1656_67B1
        h = (h ^ (h >> 15)) &* 0x2C1B_3C6D
        h = (h ^ (h >> 12)) &* 0x297A_2D39
        h ^= h >> 15
        return Float(h & 0xFF_FFFF) / Float(0x100_0000)
    }
}
