import Foundation

/// A closed outline around a centre: at angle θ its radius is `1 + Σₖ cₖ·cos kθ + sₖ·sin kθ`
/// base units, harmonic 0 being a constant.
nonisolated struct FourierOutline: Equatable, Sendable {
    var cosines: [Float]
    var sines: [Float]

    /// A circle, with room for harmonics up to `harmonicCount`.
    init(harmonicCount: Int) {
        cosines = Array(repeating: 0, count: harmonicCount + 1)
        sines = cosines
    }

    init(cosines: [Float], sines: [Float]) {
        precondition(cosines.count == sines.count, "Every harmonic has a cosine and a sine")
        self.cosines = cosines
        self.sines = sines
    }

    var harmonicCount: Int { cosines.count - 1 }

    /// The most the outline can stray from the unit circle: the constant plus the amplitude of
    /// every harmonic.
    var extent: Float {
        zip(cosines, sines).enumerated().reduce(0) { total, term in
            let (harmonic, (cosine, sine)) = term
            return total + (harmonic == 0 ? abs(cosine) : (cosine * cosine + sine * sine).squareRoot())
        }
    }

    /// How far the outline is from the unit circle at `angle` (radians).
    func offset(at angle: Float) -> Float {
        var offset: Float = 0
        for harmonic in cosines.indices {
            let phase = Float(harmonic) * angle
            offset += cosines[harmonic] * cos(phase) + sines[harmonic] * sin(phase)
        }
        return offset
    }

    /// Term by term: `self + (other − self) × fraction`.
    func interpolated(to other: FourierOutline, by fraction: Float) -> FourierOutline {
        FourierOutline(
            cosines: zip(cosines, other.cosines).map { $0 + ($1 - $0) * fraction },
            sines: zip(sines, other.sines).map { $0 + ($1 - $0) * fraction }
        )
    }

    /// This outline with each harmonic above the constant scaled by `weight(harmonic)`.
    func weighted(_ weight: (Int) -> Float) -> FourierOutline {
        FourierOutline(
            cosines: cosines.enumerated().map { $0.offset == 0 ? $0.element : $0.element * weight($0.offset) },
            sines: sines.enumerated().map { $0.offset == 0 ? $0.element : $0.element * weight($0.offset) }
        )
    }

    static func - (lhs: FourierOutline, rhs: FourierOutline) -> FourierOutline {
        FourierOutline(cosines: zip(lhs.cosines, rhs.cosines).map(-), sines: zip(lhs.sines, rhs.sines).map(-))
    }

    static func + (lhs: FourierOutline, rhs: FourierOutline) -> FourierOutline {
        FourierOutline(cosines: zip(lhs.cosines, rhs.cosines).map(+), sines: zip(lhs.sines, rhs.sines).map(+))
    }

    static func * (outline: FourierOutline, factor: Float) -> FourierOutline {
        FourierOutline(cosines: outline.cosines.map { $0 * factor }, sines: outline.sines.map { $0 * factor })
    }
}

/// The shape of the suggestions icon: a soft four-pointed spark that breathes and swirls through
/// a loop of keyframes.
nonisolated enum PicksIconOutline {
    static let harmonicCount = 10

    /// The spark at rest: four rounded points, right, up, left and down.
    static let resting: FourierOutline = {
        var outline = FourierOutline(harmonicCount: harmonicCount)
        outline.cosines[4] = 0.12
        outline.cosines[8] = 0.03
        return outline
    }()

    /// One harmonic of the spark's motion: it turns `turns` times around per cycle.
    struct Swirl {
        var harmonic: Int
        var amplitude: Float
        var turns: Int
        var offset: Float
    }

    /// The motion: a pulse of the whole shape (harmonic 0) and low harmonics that turn at
    /// different rates in both directions, so the outline never repeats within a cycle.
    static let swirls = [
        Swirl(harmonic: 0, amplitude: 0.030, turns: 2, offset: 0),
        Swirl(harmonic: 2, amplitude: 0.050, turns: 1, offset: 0),
        Swirl(harmonic: 3, amplitude: 0.040, turns: 2, offset: 1.1),
        Swirl(harmonic: 4, amplitude: 0.030, turns: -1, offset: 0.4),
        Swirl(harmonic: 5, amplitude: 0.022, turns: 3, offset: 2.0),
        Swirl(harmonic: 6, amplitude: 0.016, turns: -2, offset: 0.7),
        Swirl(harmonic: 7, amplitude: 0.012, turns: 1, offset: 2.6),
        Swirl(harmonic: 8, amplitude: 0.009, turns: -3, offset: 1.5),
        Swirl(harmonic: 9, amplitude: 0.007, turns: 2, offset: 0.2),
        Swirl(harmonic: 10, amplitude: 0.005, turns: -1, offset: 3.0),
    ]

    /// The loop the outline goes through, evenly spaced over one cycle.
    static let keyframes: [FourierOutline] = {
        let count = 12
        return (0..<count).map { index in
            let cycle = 2 * Float.pi * Float(index) / Float(count)
            var outline = resting
            for swirl in swirls {
                let angle = Float(swirl.turns) * cycle + swirl.offset
                outline.cosines[swirl.harmonic] += swirl.amplitude * cos(angle)
                if swirl.harmonic != 0 {
                    outline.sines[swirl.harmonic] += swirl.amplitude * sin(angle)
                }
            }
            return outline
        }
    }()

    /// How far the outline reaches: at rest, and at most while moving, beyond rest.
    struct Reach: Equatable {
        var resting: Float
        var breathing: Float
    }

    static let reach = Reach(
        resting: 1 + resting.extent,
        breathing: keyframes.map { ($0 - resting).extent }.max() ?? 0
    )

    /// The loop at `phase` (0..<1), interpolating between neighbouring keyframes.
    static func sample(atPhase phase: Float) -> FourierOutline {
        let position = (phase - phase.rounded(.down)) * Float(keyframes.count)
        let index = Int(position) % keyframes.count
        let next = (index + 1) % keyframes.count
        return keyframes[index].interpolated(to: keyframes[next], by: position - position.rounded(.down))
    }

    /// The outline to draw: the motion at `phase`, `amplitude` of it, with the harmonics above
    /// `modeCount` left out (the one just above it in part).
    static func shape(atPhase phase: Float, amplitude: Float, modeCount: Float) -> FourierOutline {
        let motion = (sample(atPhase: phase) - resting).weighted { harmonic in
            min(max(modeCount - Float(harmonic) + 1, 0), 1)
        }
        return resting + motion * amplitude
    }
}
