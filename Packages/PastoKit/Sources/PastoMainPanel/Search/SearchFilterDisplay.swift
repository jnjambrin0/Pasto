import Foundation
import PastoCore
import PastoSearch

/// The picture that goes with a filter in a token, a suggestion or the filter browser.
nonisolated enum SearchFilterIcon: Sendable, Equatable {
    /// An SF Symbol, by name.
    case symbol(String)
    /// An application's own icon, as stored with it.
    case image(Data)
    /// The coloured dot of a pinboard.
    case pinboardDot(PinboardColor)
    /// Nothing; a token still keeps the icon's room.
    case none
}

/// How a filter reads and looks.
nonisolated enum SearchFilterDisplay {
    /// What a filter is called where its type is not spelled out.
    ///
    /// - Parameters:
    ///   - pinboardName: The name of a pinboard, by identifier; nil when there is none.
    ///   - now: Date presets are computed again from it, so a filter made from "Today" yesterday
    ///     reads as a range of dates today.
    static func title(
        for filter: SearchFilter,
        pinboardName: (ListID) -> String?,
        now: Date,
        calendar: Calendar
    ) -> String {
        switch filter.type {
        case .app, .type, .device, .title:
            filter.value
        case .pinboard:
            pinboardName(ListID(rawValue: filter.value)) ?? filter.value
        case .date:
            dateTitle(forValue: filter.value, now: now, calendar: calendar)
        }
    }

    private static func dateTitle(forValue value: String, now: Date, calendar: Calendar) -> String {
        let preset = SearchDatePreset.allCases.first { $0.range(now: now, calendar: calendar)?.filterValue == value }
        if let preset { return preset.name }
        guard let range = SearchDateRange(filterValue: value) else { return value }
        let style = Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: calendar.locale ?? .current,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        return "\(range.start.formatted(style)) – \(range.end.formatted(style))"
    }

    /// The icon of a filter.
    ///
    /// - Parameters:
    ///   - applicationIcon: The icon of an application, by name; nil when the store has none.
    ///   - deviceType: The kind of a device, by name; nil when the store does not know it.
    ///   - pinboardColor: The colour of a pinboard, by identifier; nil when there is none.
    static func icon(
        for filter: SearchFilter,
        applicationIcon: (String) -> Data?,
        deviceType: (String) -> DeviceType?,
        pinboardColor: (ListID) -> PinboardColor?
    ) -> SearchFilterIcon {
        switch filter.type {
        case .app:
            applicationIcon(filter.value).map(SearchFilterIcon.image) ?? .symbol("app.dashed")
        case .type:
            .symbol(symbolName(forItemTypeNamed: filter.value))
        case .title:
            .none
        case .date:
            .symbol("calendar")
        case .device:
            .symbol(deviceType(filter.value).map(symbolName(for:)) ?? "macbook.and.iphone")
        case .pinboard:
            pinboardColor(ListID(rawValue: filter.value)).map(SearchFilterIcon.pinboardDot) ?? .symbol("circle.fill")
        }
    }

    private static func symbolName(for deviceType: DeviceType) -> String {
        switch deviceType {
        case .mac: "macbook"
        case .iPhone: "iphone"
        case .iPad: "ipad"
        }
    }

    private static func symbolName(forItemTypeNamed name: String) -> String {
        switch name.lowercased() {
        case "link": "link"
        case "image": "photo"
        case "color": "paintpalette"
        case "text": "text.alignleft"
        case "file": "doc"
        case "unknown": "questionmark.app"
        default: "exclamationmark.triangle.fill"
        }
    }
}
