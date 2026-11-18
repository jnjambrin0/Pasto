import Foundation
import Synchronization

/// One link download through the session, in flight: the delegate of its task. It checks every
/// redirect against the rules for link previews before the request is made, decides from the
/// response's headers how much of the body to keep (`LinkBodyCollector`), and stops the
/// transfer at the byte limit or, for a page, as soon as its `</head>` is in.
final class LinkTransfer: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var redirects = 0
        var response: HTTPURLResponse?
        var body: LinkBodyCollector?
        /// Whether a connection reached an address that is not public after all.
        var reachedLocalAddress = false
        /// Decided before the transfer ended: it was stopped, or a redirect was refused.
        var outcome: Result<LinkDownload, LinkDownloadFailure>?
        var continuation: CheckedContinuation<Result<LinkDownload, LinkDownloadFailure>, Never>?
    }

    private let state = Mutex(State())
    private let maximumRedirects: Int
    private let isAllowed: @Sendable (URL) async -> Bool
    private let allowsConnection: @Sendable (_ remoteAddress: String?, _ throughProxy: Bool) -> Bool
    private let plan: @Sendable (HTTPURLResponse) -> LinkDownloadPlan?

    /// - Parameters:
    ///   - isAllowed: Whether a redirect may be followed to an address.
    ///   - allowsConnection: Whether what came over a connection to an address may be used.
    ///   - plan: How much of a response to keep; `nil` refuses it.
    init(
        maximumRedirects: Int,
        isAllowed: @escaping @Sendable (URL) async -> Bool,
        allowsConnection: @escaping @Sendable (_ remoteAddress: String?, _ throughProxy: Bool) -> Bool,
        plan: @escaping @Sendable (HTTPURLResponse) -> LinkDownloadPlan?
    ) {
        self.maximumRedirects = maximumRedirects
        self.isAllowed = isAllowed
        self.allowsConnection = allowsConnection
        self.plan = plan
    }

    /// Runs `request` to its end. Cancelling the calling task cancels the transfer.
    func run(_ request: URLRequest, in session: URLSession) async -> Result<LinkDownload, LinkDownloadFailure> {
        let task = session.dataTask(with: request)
        task.delegate = self
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.withLock { $0.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: URLSessionTaskDelegate

    // The delegate methods take completion handlers: the compiler cannot yet bridge an `async`
    // Objective-C requirement under `NonisolatedNonsendingByDefault`.

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        Task {
            let next = await followed(request)
            completionHandler(next)
            if next == nil {
                // Nothing of the redirect's own response is wanted.
                task.cancel()
            }
        }
    }

    /// The redirect's request when it may be followed; `nil` stops the download.
    private func followed(_ request: URLRequest) async -> URLRequest? {
        let hop = state.withLock { state in
            state.redirects += 1
            return state.redirects
        }
        guard hop <= maximumRedirects else {
            decide(.failure(.tooManyRedirects))
            return nil
        }
        // Each hop gets the same scrutiny as the address that was copied: the scheme, the name
        // and what it resolves to now.
        guard let target = request.url.map(LinkDownloader.withoutCredentials), await isAllowed(target) else {
            decide(.failure(.redirectRefused))
            return nil
        }
        var next = request
        next.url = target
        next.setValue(nil, forHTTPHeaderField: "Authorization")
        next.setValue(nil, forHTTPHeaderField: "Cookie")
        return next
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // The server's certificate is checked as usual; no credential of any kind is offered.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Arrives before `didCompleteWithError`. The name was checked before each request, but the
    /// system resolves it again to connect, and a name can answer differently the second time
    /// (DNS rebinding): what was received from an address that is not public is thrown away.
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let reachedLocalAddress = metrics.transactionMetrics.contains { transaction in
            !allowsConnection(transaction.remoteAddress, transaction.isProxyConnection)
        }
        if reachedLocalAddress {
            state.withLock { $0.reachedLocalAddress = true }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, outcome) = state.withLock { state in
            let outcome: Result<LinkDownload, LinkDownloadFailure>
            if state.reachedLocalAddress {
                outcome = .failure(.reachedLocalAddress)
            } else if let decided = state.outcome {
                outcome = decided
            } else {
                outcome = Self.outcome(of: state, error: error)
            }
            let continuation = state.continuation
            state.continuation = nil
            return (continuation, outcome)
        }
        continuation?.resume(returning: outcome)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(disposition(for: response))
    }

    private func disposition(for response: URLResponse) -> URLSession.ResponseDisposition {
        guard let response = response as? HTTPURLResponse else {
            decide(.failure(.network(nil)))
            return .cancel
        }
        guard (200..<300).contains(response.statusCode) else {
            // A refused redirect arrives here as its own 3xx response; its reason stands.
            decide(.failure(.status(response.statusCode)))
            return .cancel
        }
        guard let plan = plan(response) else {
            decide(.failure(.unwantedContent))
            return .cancel
        }
        if !plan.keepsPrefix, response.expectedContentLength > plan.byteLimit {
            decide(.failure(.tooLarge))
            return .cancel
        }
        let headersOnly = state.withLock { state in
            state.response = response
            state.body = LinkBodyCollector(plan: plan, expectedLength: response.expectedContentLength)
            if plan.byteLimit == 0 {
                state.outcome = Self.outcome(of: state, error: nil)
                return true
            }
            return false
        }
        return headersOnly ? .cancel : .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let stops = state.withLock { state in
            guard state.outcome == nil, var body = state.body else { return false }
            let step = body.append(data)
            state.body = body
            switch step {
            case .more:
                return false
            case .done:
                state.outcome = Self.outcome(of: state, error: nil)
            case .tooLarge:
                state.outcome = .failure(.tooLarge)
            }
            return true
        }
        if stops {
            dataTask.cancel()
        }
    }

    // MARK: Outcome

    /// Keeps the first reason a download fails or stops for: a refused redirect is followed by
    /// its own 3xx response, which must not hide why.
    private func decide(_ outcome: Result<LinkDownload, LinkDownloadFailure>) {
        state.withLock { state in
            if state.outcome == nil {
                state.outcome = outcome
            }
        }
    }

    private static func outcome(of state: State, error: (any Error)?) -> Result<LinkDownload, LinkDownloadFailure> {
        if let error {
            return .failure(.network((error as? URLError)?.code))
        }
        guard let response = state.response, let url = response.url, let body = state.body else { return .failure(.network(nil)) }
        return .success(LinkDownload(response: response, url: url, body: body))
    }
}
