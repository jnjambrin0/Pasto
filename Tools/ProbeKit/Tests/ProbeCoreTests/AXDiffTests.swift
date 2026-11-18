import Testing
@testable import ProbeCore

@Suite struct AXDiffTests {
    private func node(_ role: String, _ frame: Frame? = nil, title: String? = nil, _ children: [AXNode] = []) -> AXNode {
        AXNode(role: role, title: title, frame: frame, children: children)
    }

    private func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Frame {
        Frame(x: x, y: y, w: w, h: h)
    }

    @Test func identicalTreesProduceAnEmptyReport() {
        let tree = node("AXApplication", nil, [
            node("AXWindow", frame(0, 785, 1728, 332), [node("AXButton", frame(10, 800, 40, 20))]),
        ])
        let report = AXDiff.compare(tree, tree)
        #expect(report.summary.matchedNodes == 3)
        #expect(report.summary.comparedFrames == 2)
        #expect(report.summary.differingFrames == 0)
        #expect(report.summary.maxDelta == 0)
        #expect(report.frameDeltas.isEmpty && report.missing.isEmpty && report.extra.isEmpty)
    }

    @Test func reportsFrameDeltasAboveTheTolerance() {
        let a = node("AXWindow", frame(0, 0, 100, 100), [
            node("AXButton", frame(10, 10, 40, 20), title: "Copy"),
            node("AXButton", frame(60, 10, 40, 20)),
        ])
        let b = node("AXWindow", frame(0, 0, 100, 100), [
            node("AXButton", frame(10.25, 10, 40, 20), title: "Copy"), // within tolerance
            node("AXButton", frame(60, 13, 44, 20)), // dy 3, dw 4
        ])
        let report = AXDiff.compare(a, b, tolerance: 0.5)
        #expect(report.frameDeltas.count == 1)
        let delta = report.frameDeltas[0]
        #expect(delta.path == "AXWindow/AXButton[1]")
        #expect(delta.dy == 3 && delta.dw == 4 && delta.dx == 0 && delta.dh == 0)
        #expect(report.summary.maxDelta == 4)
        #expect(report.summary.meanDelta == (0 + 0.25 + 4) / 3)
        #expect(report.summary.differingFrames == 1)
    }

    @Test func matchesChildrenByRoleSoOtherRolesDoNotShiftThePairing() {
        let a = node("AXWindow", nil, [
            node("AXButton", frame(0, 0, 10, 10)),
            node("AXButton", frame(20, 0, 10, 10)),
        ])
        let b = node("AXWindow", nil, [
            node("AXImage", frame(5, 5, 5, 5)),
            node("AXButton", frame(0, 0, 10, 10)),
            node("AXButton", frame(20, 0, 10, 10)),
        ])
        let report = AXDiff.compare(a, b)
        #expect(report.frameDeltas.isEmpty)
        #expect(report.missing.isEmpty)
        #expect(report.extra.map(\.path) == ["AXWindow/AXImage[0]"])
    }

    @Test func countsWholeSubtreesAsMissingOrExtra() {
        let group = node("AXGroup", nil, [node("AXButton"), node("AXButton")])
        let a = node("AXWindow", nil, [group, node("AXStaticText")])
        let b = node("AXWindow", nil, [node("AXStaticText"), node("AXStaticText", title: "new")])
        let report = AXDiff.compare(a, b)
        #expect(report.missing == [.init(path: "AXWindow/AXGroup[0]", identifier: nil, title: nil, subtreeSize: 3)])
        #expect(report.extra == [.init(path: "AXWindow/AXStaticText[1]", identifier: nil, title: "new", subtreeSize: 1)])
        #expect(report.summary.missingNodes == 3)
        #expect(report.summary.extraNodes == 1)
        #expect(report.summary.matchedNodes == 2)
    }
}
