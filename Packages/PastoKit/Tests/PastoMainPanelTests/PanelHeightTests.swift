import CoreGraphics
import Testing
@testable import PastoMainPanel

@Suite struct PanelHeightTests {
    @Test func followsThePointerInsideTheRange() {
        #expect(PanelHeight.rubberBanded(252) == 252)
        #expect(PanelHeight.rubberBanded(300.5) == 300.5)
        #expect(PanelHeight.rubberBanded(412) == 412)
    }

    @Test func givesWayByTheSquareRootOfTheOvershoot() {
        #expect(PanelHeight.rubberBanded(236) == 248)   // 252 − √16
        #expect(PanelHeight.rubberBanded(152) == 242)   // 252 − √100
        #expect(PanelHeight.rubberBanded(437) == 417)   // 412 + √25
        #expect(PanelHeight.rubberBanded(512) == 422)   // 412 + √100
        #expect(PanelHeight.rubberBanded(414) == 413)   // 412 + round(√2)
    }

    @Test func settlesInsideTheRange() {
        #expect(PanelHeight.clamped(100) == 252)
        #expect(PanelHeight.clamped(330) == 330)
        #expect(PanelHeight.clamped(900) == 412)
    }
}
