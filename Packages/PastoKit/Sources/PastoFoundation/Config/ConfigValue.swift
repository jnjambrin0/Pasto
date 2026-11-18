import Foundation

/// A setting value `UserDefaults` can hold.
public protocol ConfigValue: Sendable, Equatable {
    /// A property-list object, as `UserDefaults` requires.
    var storedRepresentation: Any { get }

    /// Fails when `storedRepresentation` is not what this type writes (a value left by another
    /// version, or edited by hand); the setting then resolves to its default.
    init?(storedRepresentation: Any)
}

// MARK: - Property-list types, stored as they are

extension Bool: ConfigValue {
    public var storedRepresentation: Any { self }

    public init?(storedRepresentation: Any) {
        guard let value = storedRepresentation as? Bool else { return nil }
        self = value
    }
}

extension Int: ConfigValue {
    public var storedRepresentation: Any { self }

    public init?(storedRepresentation: Any) {
        guard let value = storedRepresentation as? Int else { return nil }
        self = value
    }
}

extension Double: ConfigValue {
    public var storedRepresentation: Any { self }

    public init?(storedRepresentation: Any) {
        guard let value = storedRepresentation as? Double else { return nil }
        self = value
    }
}

extension String: ConfigValue {
    public var storedRepresentation: Any { self }

    public init?(storedRepresentation: Any) {
        guard let value = storedRepresentation as? String else { return nil }
        self = value
    }
}

extension Data: ConfigValue {
    public var storedRepresentation: Any { self }

    public init?(storedRepresentation: Any) {
        guard let value = storedRepresentation as? Data else { return nil }
        self = value
    }
}

extension Date: ConfigValue {
    public var storedRepresentation: Any { self }

    public init?(storedRepresentation: Any) {
        guard let value = storedRepresentation as? Date else { return nil }
        self = value
    }
}

extension Array: ConfigValue where Element == String {
    public var storedRepresentation: Any { self }

    public init?(storedRepresentation: Any) {
        guard let value = storedRepresentation as? [String] else { return nil }
        self = value
    }
}

// MARK: - Enumerations and other raw-representable types

/// Lets a type opt in with an empty conformance: `enum Density: String, ConfigValue { … }`.
extension ConfigValue where Self: RawRepresentable, RawValue: ConfigValue {
    public var storedRepresentation: Any { rawValue.storedRepresentation }

    public init?(storedRepresentation: Any) {
        guard let rawValue = RawValue(storedRepresentation: storedRepresentation) else { return nil }
        self.init(rawValue: rawValue)
    }
}
