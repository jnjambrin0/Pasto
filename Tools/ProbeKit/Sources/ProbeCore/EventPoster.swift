import CoreGraphics
import Foundation

/// Posts synthetic keyboard and mouse input at the HID event tap, as if it came from hardware.
/// Coordinates are global screen points with a top-left origin.
public enum EventPoster {
    /// Gap between the individual events of one gesture, so the receiver sees them in order.
    private static let stepMs = 8.0

    /// Presses the modifiers, taps the key for `holdMs`, then releases everything in reverse order.
    /// Returns the continuous-clock time, in milliseconds, at which the key-down was posted.
    @discardableResult
    public static func press(_ combo: KeyCombo, keyCode: UInt16, holdMs: Int) throws -> Double {
        try Permissions.requirePostEvent()
        let source = try eventSource()
        let held = KeyCombo.Modifiers.pressOrder.filter { combo.modifiers.contains($0.modifier) }

        var flags: CGEventFlags = []
        for modifier in held {
            flags.insert(modifier.flag)
            try postKey(modifier.keyCode, down: true, flags: flags, source: source)
            ProbeClock.sleep(ms: stepMs)
        }
        let keyDownMs = ProbeClock.continuousMs()
        try postKey(keyCode, down: true, flags: combo.eventFlags, source: source)
        ProbeClock.sleep(ms: Double(holdMs))
        try postKey(keyCode, down: false, flags: combo.eventFlags, source: source)
        for modifier in held.reversed() {
            ProbeClock.sleep(ms: stepMs)
            flags.remove(modifier.flag)
            try postKey(modifier.keyCode, down: false, flags: flags, source: source)
        }
        return keyDownMs
    }

    /// Presses only modifier keys (no other key), keeps them down for `holdMs`, then releases them
    /// in reverse order: what a person does to reveal hints shown while ⌘ is held. Returns the
    /// continuous-clock times of the last modifier-down and of the first modifier-up.
    @discardableResult
    public static func hold(_ modifiers: KeyCombo.Modifiers, holdMs: Int) throws -> (downMs: Double, upMs: Double) {
        try Permissions.requirePostEvent()
        let source = try eventSource()
        let held = KeyCombo.Modifiers.pressOrder.filter { modifiers.contains($0.modifier) }
        guard !held.isEmpty else { throw ProbeError.usage("name at least one modifier to hold") }
        var flags: CGEventFlags = []
        var downMs = 0.0
        for modifier in held {
            flags.insert(modifier.flag)
            downMs = ProbeClock.continuousMs()
            try postKey(modifier.keyCode, down: true, flags: flags, source: source)
            ProbeClock.sleep(ms: stepMs)
        }
        ProbeClock.sleep(ms: Double(holdMs))
        let upMs = ProbeClock.continuousMs()
        for modifier in held.reversed() {
            flags.remove(modifier.flag)
            try postKey(modifier.keyCode, down: false, flags: flags, source: source)
            ProbeClock.sleep(ms: stepMs)
        }
        return (downMs, upMs)
    }

    /// Posts a null event so that the first real event of a timed sequence does not pay for
    /// setting up the connection to the window server (≈ 50–80 ms on first use).
    public static func warmUp() throws {
        try Permissions.requirePostEvent()
        let source = try eventSource()
        CGEvent(source: source)?.post(tap: .cghidEventTap)
        ProbeClock.sleep(ms: 120)
    }

    /// Types text as Unicode key events, one character at a time, independent of the keyboard layout.
    public static func type(_ text: String, intervalMs: Int) throws {
        try Permissions.requirePostEvent()
        let source = try eventSource()
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else {
                    throw ProbeError.runtime("cannot create a keyboard event")
                }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
            ProbeClock.sleep(ms: Double(intervalMs))
        }
    }

    /// Clicks at `point`. `modifiers` are held (pressed before, released after) for the whole gesture
    /// and carried in the mouse events' flags. Returns the continuous-clock time of the first mouse-down.
    @discardableResult
    public static func click(
        at point: CGPoint, count: Int, right: Bool, modifiers: KeyCombo.Modifiers = [], downMs: Int = 30
    ) throws -> Double {
        try Permissions.requirePostEvent()
        let source = try eventSource()
        let button: CGMouseButton = right ? .right : .left
        let held = KeyCombo.Modifiers.pressOrder.filter { modifiers.contains($0.modifier) }
        var flags: CGEventFlags = []
        try postMouse(.mouseMoved, at: point, button: button, source: source)
        ProbeClock.sleep(ms: 30)
        for modifier in held {
            flags.insert(modifier.flag)
            try postKey(modifier.keyCode, down: true, flags: flags, source: source)
            ProbeClock.sleep(ms: stepMs)
        }
        var firstDownMs = 0.0
        for click in 1...max(1, count) {
            if click == 1 { firstDownMs = ProbeClock.continuousMs() }
            try postMouse(
                right ? .rightMouseDown : .leftMouseDown, at: point, button: button, clickState: click, flags: flags, source: source)
            ProbeClock.sleep(ms: Double(downMs))
            try postMouse(
                right ? .rightMouseUp : .leftMouseUp, at: point, button: button, clickState: click, flags: flags, source: source)
            ProbeClock.sleep(ms: 60)
        }
        for modifier in held.reversed() {
            flags.remove(modifier.flag)
            try postKey(modifier.keyCode, down: false, flags: flags, source: source)
            ProbeClock.sleep(ms: stepMs)
        }
        return firstDownMs
    }

    /// Posts `count` scroll-wheel events at `point` (the pointer is moved there first). `pixels`
    /// selects pixel units (trackpad-like deltas without gesture phases); otherwise line units, as
    /// a notched mouse wheel sends. Positive `deltaY` scrolls up, positive `deltaX` scrolls left.
    /// Returns the continuous-clock time of the first event.
    @discardableResult
    public static func scroll(
        at point: CGPoint, deltaX: Int32, deltaY: Int32, pixels: Bool, count: Int, intervalMs: Int
    ) throws -> Double {
        try Permissions.requirePostEvent()
        let source = try eventSource()
        try postMouse(.mouseMoved, at: point, button: .left, source: source)
        ProbeClock.sleep(ms: 30)
        var firstMs = 0.0
        for index in 0..<max(1, count) {
            guard let event = CGEvent(
                scrollWheelEvent2Source: source, units: pixels ? .pixel : .line, wheelCount: 2,
                wheel1: deltaY, wheel2: deltaX, wheel3: 0)
            else { throw ProbeError.runtime("cannot create a scroll event") }
            event.location = point
            if index == 0 { firstMs = ProbeClock.continuousMs() }
            event.post(tap: .cghidEventTap)
            if index < count - 1 { ProbeClock.sleep(ms: Double(intervalMs)) }
        }
        return firstMs
    }

    /// Moves the pointer without pressing a button; with `start`, glides there from that point so
    /// that views tracking the pointer see it enter.
    /// Returns the continuous-clock time at which the pointer reached `point`.
    @discardableResult
    public static func move(to point: CGPoint, from start: CGPoint? = nil, durationMs: Int = 200) throws -> Double {
        try Permissions.requirePostEvent()
        let source = try eventSource()
        if let start {
            let steps = max(2, Int(Double(durationMs) / stepMs))
            for step in 0..<steps {
                let progress = Double(step) / Double(steps)
                let via = CGPoint(x: start.x + (point.x - start.x) * progress, y: start.y + (point.y - start.y) * progress)
                try postMouse(.mouseMoved, at: via, button: .left, source: source)
                ProbeClock.sleep(ms: Double(durationMs) / Double(steps))
            }
        }
        let arrivedMs = ProbeClock.continuousMs()
        try postMouse(.mouseMoved, at: point, button: .left, source: source)
        return arrivedMs
    }

    /// Left-button drag along a straight line, moving at a constant speed for `durationMs`, then
    /// holding the button at the end for `holdMs` before releasing.
    /// `startHoldMs` keeps the button down at `start` before moving. Returns the continuous-clock
    /// time of the mouse-down.
    @discardableResult
    public static func drag(
        from start: CGPoint, to end: CGPoint, durationMs: Int, holdMs: Int = 0, startHoldMs: Int = 0,
        via: CGPoint? = nil, viaHoldMs: Int = 0
    ) throws -> Double {
        try Permissions.requirePostEvent()
        let source = try eventSource()
        try postMouse(.mouseMoved, at: start, button: .left, source: source)
        ProbeClock.sleep(ms: 30)
        let downMs = ProbeClock.continuousMs()
        try postMouse(.leftMouseDown, at: start, button: .left, clickState: 1, source: source)
        if startHoldMs > 0 { ProbeClock.sleep(ms: Double(startHoldMs)) }
        // With a waypoint the drag is two straight legs, each taking half of `durationMs`.
        let legs: [(from: CGPoint, to: CGPoint, pauseMs: Int)] = via.map { [(start, $0, viaHoldMs), ($0, end, 0)] }
            ?? [(start, end, 0)]
        for leg in legs {
            let legMs = Double(durationMs) / Double(legs.count)
            let steps = max(2, Int(legMs / stepMs))
            for step in 1...steps {
                ProbeClock.sleep(ms: legMs / Double(steps))
                let progress = Double(step) / Double(steps)
                let point = CGPoint(
                    x: leg.from.x + (leg.to.x - leg.from.x) * progress, y: leg.from.y + (leg.to.y - leg.from.y) * progress)
                try postMouse(.leftMouseDragged, at: point, button: .left, clickState: 1, source: source)
            }
            if leg.pauseMs > 0 {
                // Keep nudging by a point so the drag session keeps receiving events while paused.
                let until = ProbeClock.continuousMs() + Double(leg.pauseMs)
                var nudge = 1.0
                while ProbeClock.continuousMs() < until {
                    ProbeClock.sleep(ms: 50)
                    try postMouse(.leftMouseDragged, at: CGPoint(x: leg.to.x + nudge, y: leg.to.y), button: .left, clickState: 1, source: source)
                    nudge = -nudge
                }
                try postMouse(.leftMouseDragged, at: leg.to, button: .left, clickState: 1, source: source)
            }
        }
        ProbeClock.sleep(ms: 30 + Double(holdMs))
        try postMouse(.leftMouseUp, at: end, button: .left, clickState: 1, source: source)
        return downMs
    }

    private static func eventSource() throws -> CGEventSource {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ProbeError.runtime("cannot create an event source")
        }
        return source
    }

    private static func postKey(_ keyCode: UInt16, down: Bool, flags: CGEventFlags, source: CGEventSource) throws {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
            throw ProbeError.runtime("cannot create a keyboard event")
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private static func postMouse(
        _ type: CGEventType, at point: CGPoint, button: CGMouseButton, clickState: Int = 0, flags: CGEventFlags? = nil,
        source: CGEventSource
    ) throws {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
            throw ProbeError.runtime("cannot create a mouse event")
        }
        if clickState > 0 { event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState)) }
        if let flags { event.flags = flags }
        event.post(tap: .cghidEventTap)
    }
}
