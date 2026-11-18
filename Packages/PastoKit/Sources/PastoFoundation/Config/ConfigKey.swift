/// A typed setting: its `UserDefaults` key and the value it has until the user changes it.
///
/// Keys are declared next to their owner (`extension ConfigKey where Value == Bool { static let … }`),
/// not in a central registry.
public struct ConfigKey<Value: ConfigValue>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}
