import Foundation

/// Makes the two spellings of a web address that differ only in a trailing slash hash alike.
enum LinkNormalizer {
    private static let schemes: Set<String> = ["http", "https"]

    /// The string a link's checksum covers. Only `http` and `https` addresses with a host are
    /// touched, and only at the end of their path: an empty path becomes `/`, and a longer path
    /// loses its final `/`. Nothing is lowercased or re-encoded.
    static func normalized(_ string: String) -> String {
        guard let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
              let host = components.host, !host.isEmpty
        else { return string }

        // The path ends where the query or the fragment starts.
        let pathEnd = string.firstIndex { $0 == "?" || $0 == "#" } ?? string.endIndex
        let path = components.percentEncodedPath
        var normalized = string
        if path.isEmpty {
            normalized.insert("/", at: pathEnd)
        } else if path != "/", path.hasSuffix("/"), pathEnd > string.startIndex {
            let lastOfPath = string.index(before: pathEnd)
            if string[lastOfPath] == "/" {
                normalized.remove(at: lastOfPath)
            }
        }
        return normalized
    }
}
