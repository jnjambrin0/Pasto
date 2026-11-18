import CoreGraphics
import Foundation

/// One step of the pointer moving the panel.
struct StackPanelMove {
    enum Phase {
        case began
        case moved
        case ended
    }

    var phase: Phase
    /// The pointer in screen coordinates, y growing upwards.
    var pointer: CGPoint
    var time: TimeInterval
    /// False while the user holds Option.
    var isSnappingOn: Bool
}
