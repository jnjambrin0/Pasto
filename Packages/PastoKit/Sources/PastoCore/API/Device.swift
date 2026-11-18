/// A device that copied items: this Mac, or another one that reached the store through sync.
public struct Device: Sendable, Hashable {
    public var identifier: String
    public var name: String
    public var type: DeviceType
    public var appVersion: String

    public init(identifier: String, name: String, type: DeviceType, appVersion: String) {
        self.identifier = identifier
        self.name = name
        self.type = type
        self.appVersion = appVersion
    }
}

/// The raw values are persisted: never renumber them.
public enum DeviceType: Int64, Sendable, Codable {
    case mac = 0
    case iPhone
    case iPad
}
