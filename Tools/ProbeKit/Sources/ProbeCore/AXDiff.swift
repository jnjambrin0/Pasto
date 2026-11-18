import Foundation

/// Result of comparing two accessibility trees node by node.
public struct AXDiffReport: Codable, Sendable, Equatable {
    public struct FrameDelta: Codable, Sendable, Equatable {
        public let path: String
        public let identifier: String?
        public let title: String?
        public let a: Frame
        public let b: Frame
        public let dx: Double
        public let dy: Double
        public let dw: Double
        public let dh: Double

        /// Largest absolute difference among the four components.
        public var magnitude: Double { max(abs(dx), abs(dy), abs(dw), abs(dh)) }
    }

    /// A subtree present in only one of the two trees.
    public struct Unmatched: Codable, Sendable, Equatable {
        public let path: String
        public let identifier: String?
        public let title: String?
        public let subtreeSize: Int
    }

    public struct Summary: Codable, Sendable, Equatable {
        /// Nodes found in both trees.
        public let matchedNodes: Int
        /// Matched nodes whose frame is known on both sides.
        public let comparedFrames: Int
        /// Compared frames that differ by more than the tolerance.
        public let differingFrames: Int
        /// Nodes (whole subtrees counted) that exist only in A / only in B.
        public let missingNodes: Int
        public let extraNodes: Int
        public let maxDelta: Double
        public let meanDelta: Double
    }

    public let tolerance: Double
    public let summary: Summary
    public let frameDeltas: [FrameDelta]
    /// In A but not in B.
    public let missing: [Unmatched]
    /// In B but not in A.
    public let extra: [Unmatched]
}

/// Structural comparison: children are paired by role and by their index among siblings of that
/// role, so `AXWindow[0]/AXGroup[2]/AXButton[0]` names the same node in both trees.
public enum AXDiff {
    public static func compare(_ a: AXNode, _ b: AXNode, tolerance: Double = 0.5) -> AXDiffReport {
        var comparison = Comparison(tolerance: tolerance)
        comparison.visit(a, b, path: a.role)
        return comparison.report()
    }

    private struct Comparison {
        let tolerance: Double
        var matchedNodes = 0
        var comparedFrames = 0
        var deltaSum = 0.0
        var maxDelta = 0.0
        var frameDeltas: [AXDiffReport.FrameDelta] = []
        var missing: [AXDiffReport.Unmatched] = []
        var extra: [AXDiffReport.Unmatched] = []

        mutating func visit(_ a: AXNode, _ b: AXNode, path: String) {
            matchedNodes += 1
            compareFrames(a, b, path: path)

            let candidates = Dictionary(grouping: b.children, by: \.role)
            var countInA: [String: Int] = [:]
            for child in a.children {
                let index = countInA[child.role, default: 0]
                countInA[child.role] = index + 1
                let childPath = "\(path)/\(child.role)[\(index)]"
                if let partner = candidates[child.role], index < partner.count {
                    visit(child, partner[index], path: childPath)
                } else {
                    missing.append(unmatched(child, path: childPath))
                }
            }

            var countInB: [String: Int] = [:]
            for child in b.children {
                let index = countInB[child.role, default: 0]
                countInB[child.role] = index + 1
                if index >= countInA[child.role, default: 0] {
                    extra.append(unmatched(child, path: "\(path)/\(child.role)[\(index)]"))
                }
            }
        }

        private mutating func compareFrames(_ a: AXNode, _ b: AXNode, path: String) {
            guard let frameA = a.frame, let frameB = b.frame else { return }
            let delta = AXDiffReport.FrameDelta(
                path: path,
                identifier: a.identifier ?? b.identifier,
                title: a.title ?? b.title,
                a: frameA,
                b: frameB,
                dx: frameB.x - frameA.x,
                dy: frameB.y - frameA.y,
                dw: frameB.w - frameA.w,
                dh: frameB.h - frameA.h
            )
            comparedFrames += 1
            deltaSum += delta.magnitude
            maxDelta = max(maxDelta, delta.magnitude)
            if delta.magnitude > tolerance { frameDeltas.append(delta) }
        }

        private func unmatched(_ node: AXNode, path: String) -> AXDiffReport.Unmatched {
            .init(path: path, identifier: node.identifier, title: node.title, subtreeSize: node.subtreeSize)
        }

        func report() -> AXDiffReport {
            AXDiffReport(
                tolerance: tolerance,
                summary: .init(
                    matchedNodes: matchedNodes,
                    comparedFrames: comparedFrames,
                    differingFrames: frameDeltas.count,
                    missingNodes: missing.reduce(0) { $0 + $1.subtreeSize },
                    extraNodes: extra.reduce(0) { $0 + $1.subtreeSize },
                    maxDelta: maxDelta,
                    meanDelta: comparedFrames == 0 ? 0 : deltaSum / Double(comparedFrames)
                ),
                frameDeltas: frameDeltas,
                missing: missing,
                extra: extra
            )
        }
    }
}
