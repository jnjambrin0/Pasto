import Foundation

/// Turns an item's date into the text of its header. The current time is always passed in, so
/// the rules can be checked against a fixed clock.
struct ItemDateFormatter {
    private let relativeFormatter = RelativeDateTimeFormatter()
    private let abbreviatedFormatter = DateComponentsFormatter()
    private let absoluteFormatter = DateFormatter()
    private let calendar: Calendar
    private let justNow: String

    /// The units of the abbreviated form, largest first.
    private static let units: [(Calendar.Component, NSCalendar.Unit)] = [
        (.year, .year), (.month, .month), (.day, .day), (.hour, .hour), (.minute, .minute), (.second, .second),
    ]

    init(locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent, strings: CardStrings = CardStrings()) {
        var calendar = calendar
        calendar.locale = locale
        self.calendar = calendar
        justNow = strings.justNow

        relativeFormatter.dateTimeStyle = .named
        relativeFormatter.locale = locale
        relativeFormatter.calendar = calendar

        abbreviatedFormatter.unitsStyle = .abbreviated
        abbreviatedFormatter.maximumUnitCount = 1
        abbreviatedFormatter.includesApproximationPhrase = false
        abbreviatedFormatter.calendar = calendar

        absoluteFormatter.dateStyle = .medium
        absoluteFormatter.timeStyle = .short
        absoluteFormatter.locale = locale
        absoluteFormatter.calendar = calendar
        absoluteFormatter.timeZone = calendar.timeZone
    }

    /// The long form: the system's relative date ("3 minutes ago", "yesterday"), except that
    /// what the system calls "now" reads "just now".
    func relativeString(for date: Date, now: Date) -> String {
        let text = systemRelativeString(for: date, now: now)
        return text == systemRelativeString(for: now, now: now) ? justNow : text
    }

    /// The short form of the compact density: the item's age in its largest unit, such as "2m",
    /// "3h" or "5d". The formatter is given the whole age and allowed that one unit, so it is
    /// the one that reduces the rest. An age under a second has no unit and falls back to the
    /// system's relative date, without the "just now" substitution.
    func abbreviatedString(for date: Date, now: Date) -> String {
        let age = calendar.dateComponents(Set(Self.units.map(\.0)), from: date, to: now)
        guard let unit = Self.units.first(where: { (age.value(for: $0.0) ?? 0) > 0 })?.1 else {
            return systemRelativeString(for: date, now: now)
        }
        abbreviatedFormatter.allowedUnits = unit
        return abbreviatedFormatter.string(from: age) ?? systemRelativeString(for: date, now: now)
    }

    /// The full date and time, for the tooltip.
    func absoluteString(for date: Date) -> String {
        absoluteFormatter.string(from: date)
    }

    private func systemRelativeString(for date: Date, now: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
