/// The "Keep History" slider: positions 1 to 5 with a tick on each whole number (a day, a week,
/// a month, a year, forever) and the ages in between.
public nonisolated enum HistoryCapacityScale {
    public static let positions: ClosedRange<Double> = 1...5
    public static let tickCount = 5

    private static let daysPerWeek = 7
    private static let daysPerMonth = 30
    private static let daysPerYear = 365
    private static let unlimited = 0

    /// The age, in days, the slider stands for at `position`; 0 is "forever".
    ///
    /// Between a year and forever there is nothing to choose. Under the mouse the knob goes to
    /// the nearer of the two; moved any other way (the keyboard, assistive technologies), a step
    /// off either of them lands on the other one.
    ///
    /// - Parameters:
    ///   - isInteractive: Whether the mouse moves the knob: while it drags, and when it lets go
    ///     after dragging.
    ///   - previousDays: The value the slider showed before this move.
    public static func days(atPosition position: Double, isInteractive: Bool, previousDays: Int) -> Int {
        switch position {
        case ..<2:
            return step(from: max(position, 1) - 1, count: 6)
        case ..<3:
            let days = step(from: position - 2, count: 3) * daysPerWeek
            return days > 27 ? daysPerMonth : days
        case ..<4:
            let days = step(from: position - 3, count: 11) * daysPerMonth
            return days > 345 ? daysPerYear : days
        case 4:
            return daysPerYear
        case ..<5:
            if !isInteractive {
                if previousDays == daysPerYear { return unlimited }
                if previousDays == unlimited { return daysPerYear }
            }
            return position < 4.5 ? daysPerYear : unlimited
        default:
            return unlimited
        }
    }

    /// Where the knob goes for a capacity of `days`. Longer than a year is off the scale, at 0:
    /// the slider then shows it at its start.
    public static func position(forDays days: Int) -> Double {
        switch days {
        case ...0: 5
        case ..<daysPerWeek: Double(days - 1) / 6 + 1
        case ..<daysPerMonth: (Double(days) / Double(daysPerWeek) - 1) / 3 + 2
        case ..<daysPerYear: (Double(days) / Double(daysPerMonth) - 1) / 11 + 3
        case daysPerYear: 4
        default: 0
        }
    }

    /// A segment of the slider holds `count` steps after its first value, which is 1.
    private static func step(from fraction: Double, count: Double) -> Int {
        Int((fraction * count + 1).rounded())
    }
}
