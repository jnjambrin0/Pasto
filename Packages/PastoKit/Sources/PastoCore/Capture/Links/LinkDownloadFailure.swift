import Foundation

/// Why a link download gave nothing. Only these reasons reach the log, never an address.
enum LinkDownloadFailure: Error, Equatable, CustomStringConvertible {
    /// The address is not one link previews may ask (`LinkFetchPolicy`).
    case notAllowed
    /// A redirect led to an address link previews may not ask.
    case redirectRefused
    /// The connection was made to an address that is not public, although the name resolved
    /// only to public ones when it was checked.
    case reachedLocalAddress
    case tooManyRedirects
    case status(Int)
    /// Not something the download wants: its plan for the response was `nil`.
    case unwantedContent
    /// An image over its byte limit.
    case tooLarge
    /// No response, or the transfer broke off.
    case network(URLError.Code?)

    var description: String {
        switch self {
        case .notAllowed: "address not allowed"
        case .redirectRefused: "redirect to an address not allowed"
        case .reachedLocalAddress: "connected to an address that is not public"
        case .tooManyRedirects: "too many redirects"
        case .status(let code): "HTTP status \(code)"
        case .unwantedContent: "unwanted content type"
        case .tooLarge: "over the byte limit"
        case .network(let code): "network error \(code?.rawValue ?? 0)"
        }
    }
}
