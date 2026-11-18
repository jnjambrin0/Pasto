import CoreGraphics
import Testing
@testable import PastoStack

@Suite struct StackDragVelocityTests {
    private var velocity = StackDragVelocity(pointer: .zero, time: 0)

    @Test func itIsUnknownUntilTheSecondSample() {
        #expect(velocity.value.x.isNaN)
        #expect(velocity.angle(from: .horizontal) == nil)
    }

    @Test mutating func theFirstMeasurementStandsAlone() {
        velocity.update(pointer: CGPoint(x: 10, y: -5), time: 0.1)
        #expect(velocity.value == CGPoint(x: 100, y: -50))
    }

    @Test mutating func laterMeasurementsAreBlendedWithThePreviousSpeed() {
        velocity.update(pointer: CGPoint(x: 10, y: 0), time: 0.1)
        velocity.update(pointer: CGPoint(x: 30, y: 0), time: 0.2)
        // 80 % of the new 200 plus 20 % of the old 100.
        #expect(abs(velocity.value.x - 180) < 1e-9)
    }

    @Test mutating func aChangeOfDirectionOrAPauseStartsAfresh() {
        velocity.update(pointer: CGPoint(x: 10, y: 10), time: 0.1)
        velocity.update(pointer: CGPoint(x: 0, y: 20), time: 0.2)
        #expect(abs(velocity.value.x + 100) < 1e-9)

        velocity.update(pointer: CGPoint(x: -5, y: 25), time: 0.7)
        #expect(abs(velocity.value.x + 10) < 1e-9)
        #expect(abs(velocity.value.y - 10) < 1e-9)
    }

    @Test mutating func samplesTooCloseTogetherAreIgnored() {
        velocity.update(pointer: CGPoint(x: 10, y: 0), time: 0.1)
        velocity.update(pointer: CGPoint(x: 500, y: 0), time: 0.1005)
        #expect(velocity.value.x == 100)

        // The ignored sample is not the reference for the next one either.
        velocity.update(pointer: CGPoint(x: 20, y: 0), time: 0.2)
        #expect(abs(velocity.value.x - 100) < 1e-9)
    }

    @Test mutating func theAngleIsMeasuredFromTheAxis() {
        velocity.update(pointer: CGPoint(x: 10, y: -10), time: 0.1)
        #expect(abs(velocity.angle(from: .horizontal)! - .pi / 4) < 1e-9)

        velocity = StackDragVelocity(pointer: .zero, time: 0)
        velocity.update(pointer: CGPoint(x: 0, y: 10), time: 0.1)
        #expect(velocity.angle(from: .horizontal) == .pi / 2)
        #expect(velocity.angle(from: .vertical) == 0)
    }
}
