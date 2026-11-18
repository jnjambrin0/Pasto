import Darwin

/// An IPv4 or IPv6 address, as its bytes in network order.
enum IPAddress: Equatable {
    case v4([UInt8])
    case v6([UInt8])

    /// Parses a literal address, in the forms `inet_pton` accepts; `nil` for anything else.
    init?(_ string: String) {
        var v4 = in_addr()
        if inet_pton(AF_INET, string, &v4) == 1 {
            self = .v4(withUnsafeBytes(of: v4) { Array($0) })
            return
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, string, &v6) == 1 {
            self = .v6(withUnsafeBytes(of: v6) { Array($0) })
            return
        }
        return nil
    }

    /// Whether the address is on the public internet: not this Mac, not a private, shared,
    /// link-local, multicast, reserved or documentation range (RFC 6890).
    var isPublic: Bool {
        switch self {
        case .v4(let bytes):
            return Self.isPublicV4(bytes)
        case .v6(let bytes):
            // IPv4-mapped (::ffff:a.b.c.d) and IPv4-compatible (::a.b.c.d) addresses are their IPv4 address.
            if bytes[0..<10].allSatisfy({ $0 == 0 }), (bytes[10] == 0xFF && bytes[11] == 0xFF) || (bytes[10] == 0 && bytes[11] == 0) {
                let embedded = Array(bytes[12..<16])
                // `::` and `::1` are not IPv4-compatible addresses.
                if bytes[10] == 0, embedded[0] == 0, embedded[1] == 0, embedded[2] == 0 { return false }
                return Self.isPublicV4(embedded)
            }
            if bytes[0] & 0xFE == 0xFC { return false } // fc00::/7, unique local
            if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return false } // fe80::/10, link-local
            if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0xC0 { return false } // fec0::/10, site-local (deprecated)
            if bytes[0] == 0xFF { return false } // ff00::/8, multicast
            if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0D, bytes[3] == 0xB8 { return false } // 2001:db8::/32
            if bytes[0] == 0x00, bytes[1] == 0x64, bytes[2] == 0xFF, bytes[3] == 0x9B { // 64:ff9b::/96, NAT64
                return Self.isPublicV4(Array(bytes[12..<16]))
            }
            return true
        }
    }

    private static func isPublicV4(_ bytes: [UInt8]) -> Bool {
        let (a, b, c) = (bytes[0], bytes[1], bytes[2])
        switch a {
        case 0, 10, 127: return false // "this network", private, loopback
        case 100 where (64...127).contains(b): return false // 100.64.0.0/10, shared (CGNAT)
        case 169 where b == 254: return false // link-local
        case 172 where (16...31).contains(b): return false // private
        case 192 where b == 168: return false // private
        case 192 where b == 0 && (c == 0 || c == 2): return false // IETF protocol assignments, TEST-NET-1
        case 198 where b == 18 || b == 19: return false // benchmarking
        case 198 where b == 51 && c == 100: return false // TEST-NET-2
        case 203 where b == 0 && c == 113: return false // TEST-NET-3
        case 224...255: return false // multicast, reserved, broadcast
        default: return true
        }
    }
}
