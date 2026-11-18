import CoreGraphics
import Foundation

/// One drag of the stack's panel: where the panel goes as the pointer moves, including the way
/// its edges catch on the guides.
///
/// The snapping is not a pull towards nearby lines. An edge catches only when a slow movement
/// carries it across a line; it then stays there until the pointer has pulled far enough, and
/// how far depends on the direction of the pull. Everything is in screen coordinates where y
/// grows upwards.
nonisolated struct StackDrag {
    /// An edge of the panel resting on a line.
    private struct Hold {
        /// The panel's origin on the held axis.
        var origin: CGFloat
        /// Where the edge came from, as its signed distance to the line before it caught.
        var side: CGFloat
    }

    /// What is left of a hold once the pointer has pulled the panel off it.
    private struct Release {
        var velocity: CGFloat
        var origin: CGFloat
    }

    /// The origin of the panel's visible frame.
    private(set) var origin: CGPoint
    private let size: CGSize
    private let guides: [SnapGuide]
    /// From the panel's origin to the pointer; what keeps the grabbed spot under the pointer.
    private var grabOffset: CGPoint
    private var velocity: StackDragVelocity
    private var holds: [SnapAxis: Hold] = [:]
    private var releases: [SnapAxis: Release] = [:]

    init(pointer: CGPoint, time: TimeInterval, panelFrame: CGRect, guides: [SnapGuide]) {
        origin = panelFrame.origin
        size = panelFrame.size
        self.guides = guides
        grabOffset = CGPoint(x: pointer.x - panelFrame.minX, y: pointer.y - panelFrame.minY)
        velocity = StackDragVelocity(pointer: pointer, time: time)

        // A panel that was left on a guide starts on it, so that it does not come loose at the
        // first movement.
        for axis in SnapAxis.allCases {
            holds[axis] = restingHold(on: axis, frame: panelFrame)
        }
    }

    /// The panel's new origin for a pointer position. `isSnappingOn` is false while the user
    /// holds Option.
    mutating func moved(pointer: CGPoint, time: TimeInterval, isSnappingOn: Bool) -> CGPoint {
        velocity.update(pointer: pointer, time: time)
        let previousFrame = CGRect(origin: origin, size: size)
        let free = CGPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y)

        for axis in SnapAxis.allCases {
            guard let hold = holds[axis], shouldRelease(hold, on: axis, freeOrigin: free[axis], isSnappingOn: isSnappingOn) else {
                continue
            }
            holds[axis] = nil
            releases[axis] = Release(velocity: velocity.value[axis], origin: hold.origin)
            // The panel carries on from where it was held instead of jumping to the pointer.
            grabOffset[axis] = pointer[axis] - hold.origin
        }

        var target = CGPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y)
        for axis in SnapAxis.allCases {
            if let hold = holds[axis] { target[axis] = hold.origin }
        }

        if isSnappingOn {
            for axis in SnapAxis.allCases where holds[axis] == nil {
                if let release = releases[axis] {
                    guard hasExpired(release, on: axis, origin: target[axis]) else { continue }
                    releases[axis] = nil
                }
                if let hold = catchingHold(on: axis, from: previousFrame, to: CGRect(origin: target, size: size)) {
                    holds[axis] = hold
                    target[axis] = hold.origin
                }
            }
        }

        origin = target
        return target
    }

    // MARK: - Catching

    /// The hold for the first guide that the movement from `previous` to `target` carries an
    /// edge onto, if the movement is slow enough to mean it.
    private func catchingHold(on axis: SnapAxis, from previous: CGRect, to target: CGRect) -> Hold? {
        guard abs(velocity.value[axis]) <= StackMetrics.Snap.maximumSpeed else { return nil }

        for candidate in candidates(on: axis) {
            let side = previous.position(of: candidate.panelEdge) - candidate.line
            let overshoot = target.position(of: candidate.panelEdge) - candidate.line
            guard abs(side) < StackMetrics.Snap.approachDistance, side * overshoot <= 0,
                  overlaps(candidate.guide.span, target.extent(along: axis.other))
            else { continue }

            switch candidate.guide.source {
            case .window(let window):
                // Only a panel that comes from outside the window can rest against it.
                guard !previous.intersects(window) else { continue }
            case .screen(let screen):
                // A screen edge only stops a panel that is on that screen and heading out.
                let comesFromInside = candidate.panelEdge.isFarEdge ? side < 0 : side > 0
                guard previous.intersects(screen), comesFromInside else { continue }
            }
            return Hold(origin: origin(placing: candidate.panelEdge, on: candidate.line), side: side)
        }
        return nil
    }

    /// The hold for a guide the panel is already sitting on when the drag starts.
    private func restingHold(on axis: SnapAxis, frame: CGRect) -> Hold? {
        for candidate in candidates(on: axis) {
            let distance = frame.position(of: candidate.panelEdge) - candidate.line
            guard abs(distance) < StackMetrics.Snap.restingTolerance,
                  overlaps(candidate.guide.span, frame.extent(along: axis.other))
            else { continue }

            switch candidate.guide.source {
            case .window(let window):
                guard !frame.intersects(window) else { continue }
            case .screen(let screen):
                guard frame.intersects(screen) else { continue }
            }
            return Hold(origin: origin(placing: candidate.panelEdge, on: candidate.line), side: 0)
        }
        return nil
    }

    private func candidates(on axis: SnapAxis) -> [SnapCandidate] {
        guides.filter { $0.edge.axis == axis }.flatMap(\.candidates)
    }

    private func origin(placing edge: SnapEdge, on line: CGFloat) -> CGFloat {
        guard edge.isFarEdge else { return line }
        return line - (edge.axis == .horizontal ? size.width : size.height)
    }

    private func overlaps(_ span: ClosedRange<CGFloat>, _ extent: ClosedRange<CGFloat>) -> Bool {
        let tolerance = StackMetrics.Snap.spanTolerance
        return extent.lowerBound <= span.upperBound + tolerance && extent.upperBound >= span.lowerBound - tolerance
    }

    // MARK: - Letting go

    /// A held edge comes off when snapping is switched off, on a fast movement, or once the
    /// pointer has pulled far enough. Sliding along the line takes a long pull; pulling straight
    /// away takes a short one, and going back the way the edge came takes none.
    private func shouldRelease(_ hold: Hold, on axis: SnapAxis, freeOrigin: CGFloat, isSnappingOn: Bool) -> Bool {
        guard isSnappingOn, abs(velocity.value[axis]) <= StackMetrics.Snap.maximumSpeed else { return true }

        let pull = freeOrigin - hold.origin
        guard let angle = velocity.angle(from: axis), angle < StackMetrics.Snap.slidingAngle else {
            return abs(pull) >= StackMetrics.Snap.slidingPull
        }
        if angle <= StackMetrics.Snap.straightAngle, hold.side * pull > 0 {
            return true
        }
        let steepness = angle / StackMetrics.Snap.slidingAngle
        let threshold = StackMetrics.Snap.straightPull
            + (StackMetrics.Snap.slidingPull - StackMetrics.Snap.straightPull) * steepness * steepness
        return abs(pull) >= threshold
    }

    /// An edge that has just come off must not catch again at once: only after the panel has
    /// moved clear of where it was held, or turned around.
    private func hasExpired(_ release: Release, on axis: SnapAxis, origin: CGFloat) -> Bool {
        abs(origin - release.origin) >= StackMetrics.Snap.rearmDistance || velocity.value[axis] * release.velocity < 0
    }
}
