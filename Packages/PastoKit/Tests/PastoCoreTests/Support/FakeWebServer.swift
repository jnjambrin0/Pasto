import Foundation
import Synchronization
@testable import PastoCore

/// A web that lives in the test process: a `URLProtocol` that answers a session's requests from
/// routes the tests register, so link downloads run through `URLSession` — redirects, delegate
/// and all — without touching the network. Routes are keyed by host; each test uses hosts of
/// its own, so tests running at the same time do not see each other's.
final class FakeWebServer: URLProtocol, @unchecked Sendable {
    enum Route: Sendable {
        /// A whole response at once.
        case page(status: Int = 200, headers: [String: String] = ["Content-Type": "text/html; charset=utf-8"], body: Data)
        case redirect(status: Int = 302, location: String)
        /// A body of `length` bytes sent in chunks of `chunk` bytes, each made by `byte(at:)` of
        /// its offset, without `Content-Length` unless `declaresLength`.
        case stream(headers: [String: String], length: Int, chunk: Int, declaresLength: Bool, prefix: Data)
        /// The headers, then nothing until the session gives up.
        case stall(headers: [String: String])
    }

    private struct Registry {
        var routes: [String: Route] = [:]
        var requests: [URLRequest] = []
        /// Bytes each streamed URL actually handed to the session.
        var streamed: [String: Int] = [:]
    }

    private static let registry = Mutex(Registry())

    /// Answers requests for `url` (scheme, host, path and query) with `route`.
    static func route(_ url: String, _ route: Route) {
        registry.withLock { $0.routes[url] = route }
    }

    /// Every request for a URL that starts with `prefix`, in order.
    static func requests(startingWith prefix: String) -> [URLRequest] {
        registry.withLock { $0.requests.filter { $0.url?.absoluteString.hasPrefix(prefix) == true } }
    }

    /// Every request to `host`, by any scheme and port.
    static func requests(toHost host: String) -> [URLRequest] {
        registry.withLock { $0.requests.filter { $0.url.flatMap(LinkFetchPolicy.normalizedHost(of:)) == host } }
    }

    static func streamedBytes(of url: String) -> Int {
        registry.withLock { $0.streamed[url] ?? 0 }
    }

    /// A downloader whose session only reaches this server, and which takes every address the
    /// policy allows by its form as public: no name is resolved.
    static func downloader(isAllowed: @escaping @Sendable (URL) async -> Bool = { LinkFetchPolicy.allowsFetching($0) }) -> LinkDownloader {
        let configuration = LinkDownloader.configuration()
        configuration.protocolClasses = [FakeWebServer.self]
        return LinkDownloader(configuration: configuration, isAllowed: isAllowed)
    }

    // MARK: URLProtocol

    private let isStopped = Mutex(false)

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let key = url.absoluteString
        let route = Self.registry.withLock { registry in
            registry.requests.append(request)
            return registry.routes[key]
        }
        guard let route else {
            respond(status: 404, headers: ["Content-Type": "text/html"], body: Data())
            return
        }
        switch route {
        case .page(let status, let headers, let body):
            var headers = headers
            headers["Content-Length"] = String(body.count)
            respond(status: status, headers: headers, body: body)
        case .redirect(let status, let location):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": location])!
            var next = request
            next.url = URL(string: location, relativeTo: url)?.absoluteURL
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
        case .stall(let headers):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        case .stream(let headers, let length, let chunk, let declaresLength, let prefix):
            var headers = headers
            if declaresLength {
                headers["Content-Length"] = String(length)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            stream(key: key, length: length, chunk: chunk, prefix: prefix)
        }
    }

    override func stopLoading() {
        isStopped.withLock { $0 = true }
    }

    private func respond(status: Int, headers: [String: String], body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Sends the body a chunk a millisecond, as a network would, until it is all sent or the
    /// session stops the load.
    private func stream(key: String, length: Int, chunk: Int, prefix: Data) {
        let filler = Data(repeating: UInt8(ascii: "x"), count: chunk)
        let queue = DispatchQueue(label: "FakeWebServer.stream")
        let client = client
        @Sendable func send(from offset: Int) {
            queue.asyncAfter(deadline: .now() + .milliseconds(offset == 0 ? 0 : 1)) { [self] in
                guard !isStopped.withLock({ $0 }) else { return }
                guard offset < length else {
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
                var piece = Data()
                if offset < prefix.count {
                    piece.append(prefix[prefix.startIndex + offset..<prefix.startIndex + min(prefix.count, offset + chunk)])
                }
                piece.append(filler.prefix(max(0, min(chunk, length - offset) - piece.count)))
                Self.registry.withLock { $0.streamed[key, default: 0] += piece.count }
                client?.urlProtocol(self, didLoad: piece)
                send(from: offset + piece.count)
            }
        }
        send(from: 0)
    }
}
