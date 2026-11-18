import Foundation

/// A response a link preview downloaded: the page, an icon or an image.
struct LinkDownload: Sendable, Equatable {
    /// Where it came from, after redirects.
    var url: URL
    /// The `Content-Type` without parameters, in lower case; `nil` when the response has none.
    var mimeType: String?
    /// The `charset` parameter of the `Content-Type`.
    var charset: String?
    var data: Data
    /// Whether the body went on past what was kept (`LinkDownloadPlan`).
    var isTruncated = false

    init(url: URL, mimeType: String? = nil, charset: String? = nil, data: Data, isTruncated: Bool = false) {
        self.url = url
        self.mimeType = mimeType
        self.charset = charset
        self.data = data
        self.isTruncated = isTruncated
    }

    /// What `response` and the body collected for it amount to.
    init(response: HTTPURLResponse, url: URL, body: LinkBodyCollector) {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        self.init(
            url: url,
            mimeType: Self.mimeType(in: contentType),
            charset: contentType.flatMap(HTMLHead.charset(inContentType:)),
            data: body.data,
            isTruncated: body.isTruncated
        )
    }

    /// The type of a `Content-Type` value, without parameters and in lower case.
    static func mimeType(in contentType: String?) -> String? {
        guard let type = contentType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces).lowercased(), !type.isEmpty
        else { return nil }
        return type
    }
}
