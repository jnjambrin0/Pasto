import AppKit
import SwiftUI

/// The "Keep History" slider. An AppKit slider, because what happens differs between dragging
/// the knob (preview only) and letting it go (apply), which SwiftUI's slider does not tell apart
/// for clicks on the track or keyboard changes.
public struct HistoryCapacitySlider: NSViewRepresentable {
    private let model: HistoryCapacityModel
    private let accessibilityLabel: String
    private let unlimitedText: String

    /// - Parameters:
    ///   - accessibilityLabel: What VoiceOver calls the slider.
    ///   - unlimitedText: How the last position reads, where the history has no limit; the
    ///     others read as durations ("1 month"), for VoiceOver too, not as the knob's position.
    public init(model: HistoryCapacityModel, accessibilityLabel: String, unlimitedText: String) {
        self.model = model
        self.accessibilityLabel = accessibilityLabel
        self.unlimitedText = unlimitedText
    }

    /// How far the first and last tick marks sit from the slider's ends, for whoever writes a
    /// name under each tick.
    public static let tickMarkInset: CGFloat = {
        let slider = makeSlider(value: HistoryCapacityScale.positions.lowerBound)
        // The inset does not depend on the length, as long as the knob fits many times over.
        slider.frame = NSRect(x: 0, y: 0, width: 400, height: slider.fittingSize.height)
        return slider.rectOfTickMark(at: 0).midX
    }()

    public func makeNSView(context: Context) -> NSSlider {
        let slider = Self.makeSlider(value: model.sliderPosition)
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.sliderDidMove)
        slider.isContinuous = true
        slider.setAccessibilityLabel(accessibilityLabel)
        slider.onResignFocus = { [coordinator = context.coordinator] in coordinator.sliderDidLoseFocus() }
        context.coordinator.describeValue(of: slider)
        return slider
    }

    public func updateNSView(_ slider: NSSlider, context: Context) {
        let position = model.sliderPosition
        if slider.doubleValue != position {
            slider.doubleValue = position
        }
        context.coordinator.describeValue(of: slider)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(model: model, unlimitedText: unlimitedText)
    }

    private static func makeSlider(value: Double) -> FocusReportingSlider {
        let slider = FocusReportingSlider(
            value: value,
            minValue: HistoryCapacityScale.positions.lowerBound,
            maxValue: HistoryCapacityScale.positions.upperBound,
            target: nil,
            action: nil
        )
        slider.numberOfTickMarks = HistoryCapacityScale.tickCount
        return slider
    }

    public final class Coordinator: NSObject {
        private let model: HistoryCapacityModel
        private let unlimitedText: String
        /// Whether the previous change came from the mouse holding the knob.
        private var wasDragging = false

        init(model: HistoryCapacityModel, unlimitedText: String) {
            self.model = model
            self.unlimitedText = unlimitedText
        }

        /// VoiceOver reads the capacity the knob points at ("1 month"), not its position.
        func describeValue(of slider: NSSlider) {
            let description = HistoryCapacityText.value(forDays: model.shownDays) ?? unlimitedText
            if slider.accessibilityValueDescription() != description {
                slider.setAccessibilityValueDescription(description)
            }
        }

        /// A press or a drag is the mouse at work; the release that follows one still is. A
        /// step from the keyboard is applied once the knob stays put (`HistoryCapacityModel`).
        @objc func sliderDidMove(_ slider: NSSlider) {
            let input = HistoryCapacitySliderInput(eventType: NSApp.currentEvent?.type, wasDragging: wasDragging)
            wasDragging = input == .tracking
            // The knob snaps to the position of the value it landed on.
            switch input {
            case .tracking:
                slider.doubleValue = model.sliderMoved(to: slider.doubleValue, isInteractive: true, isFinal: false)
            case .released(let isInteractive):
                slider.doubleValue = model.sliderMoved(to: slider.doubleValue, isInteractive: isInteractive, isFinal: true)
            case .stepped:
                slider.doubleValue = model.sliderStepped(to: slider.doubleValue)
            }
            describeValue(of: slider)
        }

        /// A step from the keyboard waiting to be applied is applied when the focus leaves.
        func sliderDidLoseFocus() {
            model.settleSteppedChange()
        }
    }
}

/// The slider, telling when it loses the keyboard focus.
private final class FocusReportingSlider: NSSlider {
    var onResignFocus: (() -> Void)?

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        onResignFocus?()
        return true
    }
}
