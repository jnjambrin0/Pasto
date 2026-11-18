import Foundation

/// The compact form of a URL shown under a link's title: its host without `www.` and its path,
/// with the scheme only when it is not `http…`, the query, and no slashes at either end.
///
/// Every `www.` in the host goes, not just a leading one, and the scheme test is case-sensitive.
/// The path is shown decoded.
nonisolated enum ShortURL {
    static func string(for url: URL) -> String {
        var result = ""
        if let scheme = url.scheme, !scheme.hasPrefix("http") {
            result += scheme + "://"
        }
        // A URL without a host is shown from its path.
        result += (url.host(percentEncoded: false) ?? "").replacingOccurrences(of: "www.", with: "")
        result += url.path(percentEncoded: false)
        if let query = url.query(percentEncoded: true), !query.isEmpty {
            result += "?" + query
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
