/// Edits to the lists the capture rules read, which keep the order the user built them in.
enum IgnoredIdentifiers {
    /// `list` with the new `identifiers` at the end, skipping the ones it already has.
    static func adding(_ identifiers: [String], to list: [String]) -> [String] {
        identifiers.reduce(into: list) { result, identifier in
            if !result.contains(identifier) { result.append(identifier) }
        }
    }

    static func removing(_ identifiers: Set<String>, from list: [String]) -> [String] {
        list.filter { !identifiers.contains($0) }
    }

    /// `list` with `identifier` present or absent, as a switch asks.
    static func setting(_ identifier: String, included: Bool, in list: [String]) -> [String] {
        included ? adding([identifier], to: list) : removing([identifier], from: list)
    }
}
