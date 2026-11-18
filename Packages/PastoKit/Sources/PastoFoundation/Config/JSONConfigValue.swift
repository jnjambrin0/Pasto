import Foundation

/// Stores any `Codable` value as JSON data, the way the shortcuts are kept
/// (`{"keyCode":9,"internalModifiers":1179648}`).
public struct JSONConfigValue<Wrapped: Codable & Equatable & Sendable>: ConfigValue {
    public var value: Wrapped

    public init(_ value: Wrapped) {
        self.value = value
    }

    public var storedRepresentation: Any {
        let encoder = JSONEncoder()
        // Stable output, so writing an unchanged value does not look like a change.
        encoder.outputFormatting = .sortedKeys
        // A value that cannot be encoded is stored as an empty blob, which reads back as the default.
        return (try? encoder.encode(value)) ?? Data()
    }

    public init?(storedRepresentation: Any) {
        guard let data = storedRepresentation as? Data,
              let value = try? JSONDecoder().decode(Wrapped.self, from: data)
        else { return nil }
        self.value = value
    }
}
