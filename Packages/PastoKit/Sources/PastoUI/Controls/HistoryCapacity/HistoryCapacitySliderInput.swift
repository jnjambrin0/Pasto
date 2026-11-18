import AppKit

/// Where a change of the "Keep History" slider comes from, which decides what it does.
nonisolated enum HistoryCapacitySliderInput: Equatable {
    /// The mouse holds the knob, after a press on it or on the track: the value is only shown.
    case tracking
    /// The mouse went up: the value is applied. Interactive if it went up at the end of a drag.
    case released(isInteractive: Bool)
    /// The keyboard or an assistive technology moved the knob a step: the value is applied once
    /// the knob stays put a while, or the slider loses the focus.
    case stepped

    /// - Parameters:
    ///   - eventType: The event being handled when the slider reported the change, if any.
    ///   - wasDragging: Whether the previous change was `tracking`.
    init(eventType: NSEvent.EventType?, wasDragging: Bool) {
        switch eventType {
        case .leftMouseDown, .leftMouseDragged:
            self = .tracking
        case .leftMouseUp:
            self = .released(isInteractive: wasDragging)
        default:
            self = .stepped
        }
    }
}
