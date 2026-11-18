import Foundation

/// How a history capacity reads: "3 days", "2 weeks". Durations are worded by the system, in its
/// language; the words for "no limit" belong to whoever shows the slider.
public nonisolated enum HistoryCapacityText {
    /// The capacity in its natural unit: days up to a week, then whole weeks and months, and a
    /// year. Longer than a year is counted in days. Nil when there is no limit.
    public static func components(forDays days: Int) -> DateComponents? {
        switch days {
        case ...0: nil
        case ..<7: DateComponents(day: days)
        case ..<30: DateComponents(weekOfMonth: days / 7)
        case ..<365: DateComponents(month: days / 30)
        case 365: DateComponents(year: 1)
        default: DateComponents(day: days)
        }
    }

    /// Nil when there is no limit.
    public static func value(forDays days: Int) -> String? {
        components(forDays: days).flatMap(wording)
    }

    /// The names under the slider's first four ticks: a day, a week, a month and a year.
    public static var unitTickLabels: [String] {
        let units = [DateComponents(day: 1), DateComponents(weekOfMonth: 1), DateComponents(month: 1), DateComponents(year: 1)]
        return units.map { unitName(wording($0) ?? "") }
    }

    /// Worded in the language the app is shown in, which is not always the system's region
    /// (a per-app language, or Spanish text on an English-region Mac).
    private static func wording(_ components: DateComponents) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        formatter.calendar = calendar
        return formatter.string(from: components)
    }

    /// "1 day" → "Day": the count and the spaces around it go, and the words are capitalised.
    static func unitName(_ duration: String) -> String {
        duration.trimmingCharacters(in: CharacterSet.decimalDigits.union(.whitespaces)).capitalized
    }
}
