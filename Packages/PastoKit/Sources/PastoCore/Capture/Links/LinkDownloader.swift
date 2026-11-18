import Foundation

/// Downloads what link previews need — a page, its icon, its image — through a session of its
/// own that keeps nothing between requests and sends nothing of the user's: no cookies, no
/// cache, no credentials. Every address, the copied one and each redirect, must pass
/// `isAllowed` before it is requested, and what comes over a connection is used only if
/// `allowsConnection` takes the address it reached.
///
/// Each address is asked as it comes, `http` or `https`. App Transport Security then treats a
/// plain-HTTP request as it treats Link Presentation's web views in the app (Pasto has no
/// exception): a site on the system's HSTS list is asked over HTTPS, and any other is refused
/// (`NSURLErrorAppTransportSecurityRequiresSecureConnection`), so its link has no preview.
struct LinkDownloader: Sendable {
    /// Link Presentation's user agent for the page, as of macOS 27.2: sites answer it with the
    /// tags link previews read, the same page Link Presentation gets.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_1) AppleWebKit/601.2.4 (KHTML, like Gecko) "
        + "Version/9.0.1 Safari/601.2.4 facebookexternalhit/1.1 Facebot Twitterbot/1.0"
    /// What Link Presentation accepts for the page; icons and images accept anything.
    static let pageAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    static let imageAccept = "*/*"

    /// Link Presentation's own time limit.
    static let timeout: TimeInterval = 30
    /// More hops than any real link needs (browsers stop at 20).
    static let maximumRedirects = 10

    let session: URLSession
    let isAllowed: @Sendable (URL) async -> Bool
    let allowsConnection: @Sendable (_ remoteAddress: String?, _ throughProxy: Bool) -> Bool

    /// - Parameters:
    ///   - configuration: `configuration()` unless a test needs another.
    ///   - isAllowed: Whether an address may be requested; by default, a public web address
    ///     that resolves only to public addresses (`LinkFetchPolicy`).
    ///   - allowsConnection: Whether what came over a connection to an address may be used; by
    ///     default, only from public addresses or through a proxy.
    init(
        configuration: URLSessionConfiguration = LinkDownloader.configuration(),
        isAllowed: @escaping @Sendable (URL) async -> Bool = LinkDownloader.isPublicWebAddress,
        allowsConnection: @escaping @Sendable (_ remoteAddress: String?, _ throughProxy: Bool) -> Bool = LinkFetchPolicy.allowsConnection(to:throughProxy:)
    ) {
        session = URLSession(configuration: configuration)
        self.isAllowed = isAllowed
        self.allowsConnection = allowsConnection
    }

    /// An ephemeral session that stores, sends and accepts nothing of the user's.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return configuration
    }

    static func isPublicWebAddress(_ url: URL) async -> Bool {
        guard LinkFetchPolicy.allowsFetching(url) else { return false }
        return await LinkFetchPolicy.resolvesToPublicAddresses(url)
    }

    /// Downloads `url`, keeping of the response what `plan` decides from its headers.
    func download(
        _ url: URL,
        accept: String,
        plan: @escaping @Sendable (HTTPURLResponse) -> LinkDownloadPlan?
    ) async -> Result<LinkDownload, LinkDownloadFailure> {
        let url = Self.withoutCredentials(url)
        guard await isAllowed(url) else { return .failure(.notAllowed) }
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let transfer = LinkTransfer(
            maximumRedirects: Self.maximumRedirects, isAllowed: isAllowed, allowsConnection: allowsConnection, plan: plan
        )
        return await transfer.run(request, in: session)
    }

    /// `url` without a user name or password: a preview never signs in anywhere.
    static func withoutCredentials(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.user != nil || components.password != nil
        else { return url }
        components.user = nil
        components.password = nil
        return components.url ?? url
    }
}
