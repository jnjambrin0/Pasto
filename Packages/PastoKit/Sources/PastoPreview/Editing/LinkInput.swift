import Foundation

/// What the link editor accepts.
nonisolated enum LinkInput {
    /// The address typed in the editor, or `nil` while it cannot be saved. Text without a scheme
    /// is taken as an `https` address; any scheme is accepted and no host is required.
    static func url(from text: String) -> URL? {
        guard let url = URL(string: text) else { return nil }
        return url.scheme == nil ? URL(string: "https://" + url.absoluteString) : url
    }
}
