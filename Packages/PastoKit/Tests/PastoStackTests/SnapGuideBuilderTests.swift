import CoreGraphics
import Testing
@testable import PastoStack

@Suite struct SnapGuideBuilderTests {
    private func window(_ frame: CGRect, layer: Int = 0, alpha: Double = 1, number: Int) -> SnapWindow {
        SnapWindow(frame: frame, layer: layer, alpha: alpha, number: number)
    }

    @Test func aScreenGivesItsFourEdgesAtFullLength() {
        let screen = CGRect(x: 0, y: 25, width: 1000, height: 700)
        let guides = SnapGuideBuilder.guides(screens: [screen], windows: [], ownWindowNumber: 0)

        #expect(guides == [
            SnapGuide(edge: .left, line: 0, span: 25...725, source: .screen(screen)),
            SnapGuide(edge: .right, line: 1000, span: 25...725, source: .screen(screen)),
            SnapGuide(edge: .bottom, line: 25, span: 0...1000, source: .screen(screen)),
            SnapGuide(edge: .top, line: 725, span: 0...1000, source: .screen(screen)),
        ])
    }

    @Test func onlyOrdinaryVisibleWindowsOtherThanTheStackCount() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 200)
        let guides = SnapGuideBuilder.guides(
            screens: [],
            windows: [
                window(frame, layer: 25, number: 1),
                window(frame, alpha: 0.1, number: 2),
                window(frame, number: 3),
                window(frame.offsetBy(dx: 500, dy: 0), alpha: 0.2, number: 4),
            ],
            ownWindowNumber: 3
        )
        #expect(guides.count == 4)
        #expect(guides.allSatisfy { $0.source == .window(frame.offsetBy(dx: 500, dy: 0)) })
    }

    @Test func screenGuidesComeBeforeWindowGuidesAndFrontWindowsFirst() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let front = CGRect(x: 100, y: 100, width: 100, height: 100)
        let back = CGRect(x: 600, y: 100, width: 100, height: 100)
        let guides = SnapGuideBuilder.guides(
            screens: [screen],
            windows: [window(front, number: 1), window(back, number: 2)],
            ownWindowNumber: 0
        )
        #expect(guides.map(\.source) == Array(repeating: .screen(screen), count: 4)
            + Array(repeating: .window(front), count: 4)
            + Array(repeating: .window(back), count: 4))
    }

    @Test func aWindowInFrontHidesTheStretchOfAnEdgeItCovers() {
        let back = CGRect(x: 0, y: 0, width: 400, height: 400)
        // Straddles the back window's bottom edge between x = 100 and x = 200.
        let front = CGRect(x: 100, y: -50, width: 100, height: 200)
        let guides = SnapGuideBuilder.guides(
            screens: [],
            windows: [window(front, number: 1), window(back, number: 2)],
            ownWindowNumber: 0
        )
        let backGuides = guides.filter { $0.source == .window(back) }

        #expect(backGuides.filter { $0.edge == .bottom }.map(\.span) == [0...100, 200...400])
        #expect(backGuides.filter { $0.edge == .top }.map(\.span) == [0...400])
        #expect(backGuides.filter { $0.edge == .left }.map(\.span) == [0...400])
    }

    @Test func aWindowThatOnlyTouchesAnEdgeHidesNothing() {
        let back = CGRect(x: 0, y: 0, width: 400, height: 400)
        // Sits on top of the back window: its bottom edge runs along the other's top edge.
        let front = CGRect(x: 100, y: 400, width: 100, height: 100)
        let guides = SnapGuideBuilder.guides(
            screens: [],
            windows: [window(front, number: 1), window(back, number: 2)],
            ownWindowNumber: 0
        )
        #expect(guides.filter { $0.source == .window(back) && $0.edge == .top }.map(\.span) == [0...400])
    }

    @Test func aWindowEdgeTakesThePanelFlushOrNextToIt() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 200)
        let right = SnapGuide(edge: .right, line: 300, span: 100...300, source: .window(frame))
        let bottom = SnapGuide(edge: .bottom, line: 100, span: 100...300, source: .window(frame))

        #expect(right.candidates.map(\.panelEdge) == [.right, .left])
        #expect(right.candidates.map(\.line) == [300, 301])
        #expect(bottom.candidates.map(\.panelEdge) == [.bottom, .top])
        #expect(bottom.candidates.map(\.line) == [100, 99])
    }

    @Test func aScreenEdgeOnlyTakesTheSameEdgeOfThePanel() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let guide = SnapGuide(edge: .top, line: 700, span: 0...1000, source: .screen(screen))
        #expect(guide.candidates == [SnapCandidate(panelEdge: .top, line: 700, guide: guide)])
    }
}
