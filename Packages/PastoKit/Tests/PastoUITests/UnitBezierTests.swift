import Testing
@testable import PastoUI

@Suite struct UnitBezierTests {
    @Test func endpointsAreExact() {
        let curve = UnitBezier(0.2, 0.8, 0.2, 1.0)
        #expect(curve.value(at: 0) == 0)
        #expect(curve.value(at: 1) == 1)
        #expect(curve.value(at: -0.5) == 0)
        #expect(curve.value(at: 1.5) == 1)
    }

    @Test func linearCurveIsIdentity() {
        for step in 0...10 {
            let progress = Double(step) / 10
            #expect(abs(UnitBezier.linear.value(at: progress) - progress) < 1e-6)
        }
    }

    /// Reference values computed from the closed-form curve definition.
    @Test func matchesKnownValues() {
        // ease-in-out is symmetric around the midpoint.
        #expect(abs(UnitBezier.easeInEaseOut.value(at: 0.5) - 0.5) < 1e-6)
        #expect(abs(UnitBezier.easeInEaseOut.value(at: 0.25) - 0.1291) < 1e-3)
        #expect(abs(UnitBezier.easeInEaseOut.value(at: 0.75) - 0.8709) < 1e-3)
        // The panel's show curve front-loads the motion.
        let show = UnitBezier(0.2, 0.8, 0.2, 1.0)
        #expect(show.value(at: 0.25) > 0.7)
        #expect(show.value(at: 0.5) > 0.9)
    }

    @Test func isMonotonicForStandardCurves() {
        for curve in [UnitBezier.easeIn, .easeOut, .easeInEaseOut, UnitBezier(0.2, 0.8, 0.2, 1.0)] {
            var previous = 0.0
            for step in 1...200 {
                let value = curve.value(at: Double(step) / 200)
                #expect(value >= previous - 1e-9)
                previous = value
            }
        }
    }
}
