import Foundation

/// Takes the site's own name off a page title, as Link Presentation does (as of macOS 27.2):
/// "Y Combinator | Hacker News" on news.ycombinator.com is "Hacker News",
/// "GitHub - swiftlang/swift: …" on github.com is "swiftlang/swift: …".
///
/// The title must split in two at a separator that appears in it exactly once —
/// " | ", " - ", " – ", " — ", ": " or " » " — and one of the halves must be the site's name:
/// the name of its registrable domain ("ycombinator", or "ycombinator.com"), compared without
/// case, accents, spaces or punctuation and allowing for a few letters more or less ("Example
/// Blog", "The Example"). Then the other half is the title. `og:site_name` plays no part.
enum LinkTitleSiteName {
    static let separators = [" | ", " - ", " – ", " — ", ": ", " » "]

    /// How different a half may be from the site's name and still be it: edits over length.
    /// Link Presentation took "Localtest Online" for localtest.me (6 of 15) but not
    /// "Localtest Abcdefgh" (8 of 17) or "Local" (4 of 9).
    static let maximumDifference = 0.4

    /// `title` without the site's name, or as it is.
    static func removed(from title: String, host: String?) -> String {
        guard let host, let names = siteNames(of: host) else { return title }
        var best: (difference: Double, rest: String)?
        for separator in separators {
            let parts = title.components(separatedBy: separator)
            guard parts.count == 2 else { continue }
            for (name, rest) in [(parts[0], parts[1]), (parts[1], parts[0])] {
                let rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                let difference = names.map { Self.difference(between: normalized(name), and: $0) }.min() ?? 1
                guard !rest.isEmpty, difference <= maximumDifference, difference < best?.difference ?? .infinity else { continue }
                best = (difference, rest)
            }
        }
        return best?.rest ?? title
    }

    /// The site's name and its registrable domain, normalized; `nil` for an address or a host
    /// without a domain. The registrable domain is the last two labels, or three under the
    /// two-level suffixes of country domains ("bbc.co.uk", "abc.net.au").
    static func siteNames(of host: String) -> [String]? {
        guard IPAddress(host) == nil else { return nil }
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        let isCountrySuffix = labels.count >= 3 && labels[labels.count - 1].count == 2
            && countrySecondLevels.contains(labels[labels.count - 2])
        let registrable = labels.suffix(isCountrySuffix ? 3 : 2)
        guard let name = registrable.first else { return nil }
        return [normalized(name), normalized(registrable.joined(separator: "."))]
    }

    /// The second levels countries open to registration under them, as in "co.uk" or "com.es".
    private static let countrySecondLevels: Set<String> = [
        "co", "com", "net", "org", "gov", "gob", "edu", "ac", "or", "ne", "go", "mil", "nom", "ltd", "plc", "sch", "info", "biz",
    ]

    /// Letters and digits only, without case or accents.
    static func normalized(_ text: String) -> String {
        String(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Edit distance over the length of the longer one: 0 for equal, 1 for nothing in common.
    static func difference(between first: String, and second: String) -> Double {
        let a = Array(first.unicodeScalars), b = Array(second.unicodeScalars)
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 0 }
        // Levenshtein, a row at a time.
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return Double(previous[b.count]) / Double(longest)
    }
}
