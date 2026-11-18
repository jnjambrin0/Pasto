import Foundation

/// Standard output for results, standard error for diagnostics.
public enum Console {
    /// Prints a line and flushes, so that piped consumers see it immediately.
    public static func out(_ text: String) {
        print(text)
        fflush(nil)
    }

    public static func error(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    public static func json<Value: Encodable>(_ value: Value) throws {
        out(try JSONText.pretty(value))
    }
}

public enum JSONText {
    /// Pretty-printed JSON with stable key order, for command results.
    public static func pretty<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// One compact JSON object on a single line, for newline-delimited event logs.
    public static func line(_ object: [String: Any]) -> String {
        let normalized = normalize(object)
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys, .withoutEscapingSlashes])
        else {
            return #"{"error":"event could not be encoded as JSON"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// `JSONSerialization` prints a `Double` with 17 significant digits (`1.8640000000000001`);
    /// going through a decimal number keeps the shortest form that reads back the same.
    private static func normalize(_ value: Any) -> Any {
        switch value {
        case let double as Double: NSDecimalNumber(string: "\(double)")
        case let array as [Any]: array.map(normalize)
        case let dictionary as [String: Any]: dictionary.mapValues(normalize)
        default: value
        }
    }
}
