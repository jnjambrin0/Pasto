import Foundation

/// Minimal `--option value` / `--flag` / positional parser shared by both executables.
public struct CommandLineArguments: Sendable {
    public struct Spec: Sendable {
        public var valueOptions: Set<String>
        public var flags: Set<String>

        public init(valueOptions: Set<String> = [], flags: Set<String> = []) {
            self.valueOptions = valueOptions
            self.flags = flags
        }
    }

    public private(set) var positionals: [String] = []
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    public init(_ raw: [String], spec: Spec) throws {
        var index = 0
        while index < raw.count {
            let token = raw[index]
            index += 1
            guard token.hasPrefix("--"), token.count > 2 else {
                if token == "--" {
                    positionals.append(contentsOf: raw[index...])
                    break
                }
                positionals.append(token)
                continue
            }
            let body = token.dropFirst(2)
            let name = String(body.prefix { $0 != "=" })
            let inlineValue = body.contains("=") ? String(body.drop { $0 != "=" }.dropFirst()) : nil
            if spec.flags.contains(name) {
                guard inlineValue == nil else { throw ProbeError.usage("--\(name) does not take a value") }
                flags.insert(name)
            } else if spec.valueOptions.contains(name) {
                if let inlineValue {
                    values[name] = inlineValue
                } else if index < raw.count {
                    values[name] = raw[index]
                    index += 1
                } else {
                    throw ProbeError.usage("--\(name) needs a value")
                }
            } else {
                throw ProbeError.usage("unknown option --\(name)")
            }
        }
    }

    public func flag(_ name: String) -> Bool {
        flags.contains(name)
    }

    public func string(_ name: String) -> String? {
        values[name]
    }

    public func requiredString(_ name: String) throws -> String {
        guard let value = values[name] else { throw ProbeError.usage("missing --\(name)") }
        return value
    }

    public func int(_ name: String) throws -> Int? {
        guard let text = values[name] else { return nil }
        guard let value = Int(text) else { throw ProbeError.usage("--\(name) expects an integer, got '\(text)'") }
        return value
    }

    public func double(_ name: String) throws -> Double? {
        guard let text = values[name] else { return nil }
        guard let value = Double(text), value.isFinite else {
            throw ProbeError.usage("--\(name) expects a number, got '\(text)'")
        }
        return value
    }

    /// A strictly positive number, or `fallback` when the option is absent.
    public func positiveDouble(_ name: String, default fallback: Double) throws -> Double {
        let value = try double(name) ?? fallback
        guard value > 0 else { throw ProbeError.usage("--\(name) must be greater than zero") }
        return value
    }

    /// A non-negative integer, or `fallback` when the option is absent.
    public func nonNegativeInt(_ name: String, default fallback: Int) throws -> Int {
        let value = try int(name) ?? fallback
        guard value >= 0 else { throw ProbeError.usage("--\(name) must not be negative") }
        return value
    }

    public func positional(_ index: Int, named label: String) throws -> String {
        guard index < positionals.count else { throw ProbeError.usage("missing <\(label)>") }
        return positionals[index]
    }

    public func expectPositionals(_ count: Int) throws {
        guard positionals.count <= count else {
            throw ProbeError.usage("unexpected argument '\(positionals[count])'")
        }
    }
}
