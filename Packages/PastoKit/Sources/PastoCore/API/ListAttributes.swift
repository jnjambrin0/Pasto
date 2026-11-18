/// The settings of a list, which depend on its type.
public enum ListAttributes: Sendable, Hashable, Codable {
    case clipboard(capacity: HistoryCapacity)
    case pinboard(color: PinboardColor)
}

/// How long the clipboard history keeps items that are not on a pinboard: an age in days. The
/// named values are the ticks of "Keep History"; the slider also produces the ages in between.
public struct HistoryCapacity: Sendable, Hashable, Codable {
    /// 0 keeps everything.
    public let days: Int

    public init(days: Int) {
        self.days = max(days, 0)
    }

    public static let day = HistoryCapacity(days: 1)
    public static let week = HistoryCapacity(days: 7)
    public static let month = HistoryCapacity(days: 30)
    public static let year = HistoryCapacity(days: 365)
    public static let unlimited = HistoryCapacity(days: 0)

    public var isUnlimited: Bool { days == 0 }

    // Encoded as the bare number of days, which is what the list's attributes hold.

    public init(from decoder: any Decoder) throws {
        self.init(days: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(days)
    }
}

/// The label colors a pinboard can have. The raw values are persisted: never renumber them.
public enum PinboardColor: Int, Sendable, CaseIterable, Codable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case gray
}
