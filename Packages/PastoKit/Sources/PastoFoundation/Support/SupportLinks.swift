import Foundation

/// Where a user reaches Pasto's author. These only build the links the user opens: Pasto sends
/// nothing by itself.
public nonisolated enum SupportLinks {
    /// Pasto's website; every other web address hangs from it.
    public static let website = URL(string: "https://pasto.jnjambrino.com")!

    /// Where problem reports are written to.
    public static let contactAddress = "hello@jnjambrino.com"

    /// The contact page, with the versions in its query (`app`, `macos`, `mac`) so that the page
    /// can fill them in.
    public static func contactPage(details: SystemDetails) -> URL {
        var components = URLComponents(url: website.appending(path: "contact"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "app", value: details.appVersion),
            URLQueryItem(name: "macos", value: details.systemVersion),
            URLQueryItem(name: "mac", value: details.macModel),
        ]
        return components.url!
    }

    /// A new email to `contactAddress`. The body starts with `prompt`, for the user to write
    /// under, and ends with the versions.
    public static func email(subject: String, prompt: String, details: SystemDetails) -> URL {
        let body = "\(prompt)\n\n\n—\n" + details.lines.joined(separator: "\n") + "\n"
        let query = [("subject", subject), ("body", body)]
            .map { "\($0)=\(mailtoEncoded($1))" }
            .joined(separator: "&")
        return URL(string: "mailto:\(contactAddress)?\(query)")!
    }

    /// RFC 6068: in a `mailto` header value everything but unreserved characters is escaped,
    /// so that `&`, `=`, `+`, `#` and line breaks reach the mail app as written.
    static func mailtoEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // Only ASCII letters and digits are unreserved; `alphanumerics` also has the others.
        return value.unicodeScalars.map { scalar in
            scalar.isASCII && allowed.contains(scalar)
                ? String(scalar)
                : String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
        }.joined()
    }
}

/// What a problem report needs to say about this copy of Pasto and this Mac. Nothing else: no
/// identifiers, no settings, no history.
public nonisolated struct SystemDetails: Equatable, Sendable {
    /// "1.0.0 (311)".
    public let appVersion: String
    /// "27.2 (26C123)".
    public let systemVersion: String
    /// "Mac15,3".
    public let macModel: String

    public init(appVersion: String, systemVersion: String, macModel: String) {
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.macModel = macModel
    }

    public static func current(bundle: Bundle = .main) -> SystemDetails {
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let systemNumber = system.patchVersion == 0
            ? "\(system.majorVersion).\(system.minorVersion)"
            : "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        return SystemDetails(
            appVersion: "\(version) (\(build))",
            systemVersion: sysctlString("kern.osversion").map { "\(systemNumber) (\($0))" } ?? systemNumber,
            macModel: sysctlString("hw.model") ?? "Mac"
        )
    }

    /// One per line, as they end a report.
    public var lines: [String] {
        ["Pasto \(appVersion)", "macOS \(systemVersion)", macModel]
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }
}
