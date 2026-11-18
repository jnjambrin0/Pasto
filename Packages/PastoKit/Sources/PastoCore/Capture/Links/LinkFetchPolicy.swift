import Darwin
import Foundation

/// Which copied links Pasto asks the network about. Only web pages on the public internet: a copy
/// must never make Pasto knock on the Mac itself, a device of the user's network or a service
/// that is not a web page — an address can do something just by being requested.
///
/// Any other link gets no page preview: the user's privacy comes before a richer card.
enum LinkFetchPolicy {
    private static let schemes: Set<String> = ["http", "https"]

    /// Names that only mean something on the local network, whatever the DNS says about them.
    private static let localSuffixes = [".local", ".localhost", ".localdomain", ".internal", ".lan", ".home", ".home.arpa", ".corp", ".intranet"]

    /// Whether the address itself allows a request: `http` or `https`, a host that is a domain
    /// name with a dot in it, and not a name or an address of the local network.
    static func allowsFetching(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = normalizedHost(of: url)
        else { return false }
        if let address = IPAddress(host) {
            return address.isPublic
        }
        // A single label ("intranet", "router") is resolved through the search domains of the
        // local network; "localhost" and the local suffixes never leave it.
        guard host.contains("."), host != "localhost" else { return false }
        return !localSuffixes.contains { host.hasSuffix($0) }
    }

    /// The host in lowercase, without IPv6 brackets or a trailing dot; `nil` when there is none.
    static func normalizedHost(of url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host.isEmpty ? nil : host
    }

    /// Whether every address the host resolves to is public: a public name can still point into
    /// the local network. Resolution that fails or takes longer than `timeout` counts as no.
    static func resolvesToPublicAddresses(_ url: URL, timeout: Duration = .seconds(5)) async -> Bool {
        guard let host = normalizedHost(of: url) else { return false }
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    // `getaddrinfo` blocks; it gets a thread of its own rather than one of the pool's.
                    DispatchQueue.global(qos: .utility).async {
                        let addresses = resolve(host)
                        continuation.resume(returning: !addresses.isEmpty && addresses.allSatisfy(\.isPublic))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? false
        }
    }

    /// Whether a connection the system made for a link preview went where previews may go: to a
    /// public address. Through a proxy the address is the proxy's — one the user set up — and
    /// says nothing about the page; without an address there was no connection.
    static func allowsConnection(to remoteAddress: String?, throughProxy: Bool) -> Bool {
        guard !throughProxy, let remoteAddress else { return true }
        return IPAddress(remoteAddress)?.isPublic ?? false
    }

    private static func resolve(_ host: String) -> [IPAddress] {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [IPAddress] = []
        for entry in sequence(first: first, next: { $0.pointee.ai_next }) {
            guard let address = entry.pointee.ai_addr else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    addresses.append(.v4(withUnsafeBytes(of: $0.pointee.sin_addr) { Array($0) }))
                }
            case AF_INET6:
                address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    addresses.append(.v6(withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }))
                }
            default:
                continue
            }
        }
        return addresses
    }
}
