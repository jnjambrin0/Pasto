import Foundation

/// Where a page's icon may be, best first, ranked as Link Presentation ranks them (as of
/// macOS 27.2):
///
/// 1. `<link rel="apple-touch-icon">` and `rel="apple-touch-icon-precomposed"` before any
///    `rel="icon"` or `"shortcut icon"` (those exact values), whatever their sizes;
/// 2. within each, the larger declared width first (`sizes="180x180"`, first size listed); an
///    apple-touch icon without sizes counts as 60 px and any other icon as 0;
/// 3. at the same size, precomposed first, then the order of the page.
///
/// Then, as a last resort, the places browsers look without being told:
/// `/apple-touch-icon-precomposed.png`, `/apple-touch-icon.png` and `/favicon.ico`, on the site
/// of the address asked for, not the one it redirected to.
///
/// Only links in the head count, as a browser's parser draws it (`HTMLHeadScanner`).
/// `rel="mask-icon"` and other icon kinds are not icons here, and SVG icons are skipped: the
/// system cannot decode them, so Link Presentation never shows one either.
enum LinkIconChoice {
    static let fallbackPaths = ["/apple-touch-icon-precomposed.png", "/apple-touch-icon.png", "/favicon.ico"]

    /// The width an apple-touch icon without `sizes` is taken to have.
    static let undeclaredTouchIconWidth = 60

    /// - Parameters:
    ///   - pageURL: Where the page came from, after redirects: declared icons resolve against it
    ///     (or its `<base>`).
    ///   - fallbackURL: The address asked for, where the undeclared places are.
    static func candidates(in head: HTMLHead, pageURL: URL, fallbackURL: URL) -> [URL] {
        let base = head.baseHref.flatMap { LinkPageDescription.resolved($0, against: pageURL) } ?? pageURL
        let ranked = head.links.enumerated().compactMap { order, link in
            rank(of: link, order: order, base: base)
        }
        .sorted { ($0.isTouchIcon ? 0 : 1, -$0.width, $0.isPrecomposed ? 0 : 1, $0.order) < ($1.isTouchIcon ? 0 : 1, -$1.width, $1.isPrecomposed ? 0 : 1, $1.order) }
        .map(\.url)
        let fallbacks = fallbackPaths.compactMap { URL(string: $0, relativeTo: fallbackURL)?.absoluteURL }
        var seen = Set<URL>()
        return (ranked + fallbacks).filter { seen.insert($0).inserted }
    }

    private struct Rank {
        let isTouchIcon: Bool
        let isPrecomposed: Bool
        let width: Int
        let order: Int
        let url: URL
    }

    private static func rank(of link: HTMLHead.Link, order: Int, base: URL) -> Rank? {
        guard link.isInHead else { return nil }
        // Only these exact values, in any case: Link Presentation takes no "alternate icon",
        // "icon shortcut" or "apple-touch-icon icon".
        let isPrecomposed = link.rel == "apple-touch-icon-precomposed"
        let isTouchIcon = isPrecomposed || link.rel == "apple-touch-icon"
        guard isTouchIcon || link.rel == "icon" || link.rel == "shortcut icon" else { return nil }
        guard !isSVG(link), let url = LinkPageDescription.resolved(link.href, against: base) else { return nil }
        let width = link.sizes.flatMap(declaredWidth) ?? (isTouchIcon ? undeclaredTouchIconWidth : 0)
        return Rank(isTouchIcon: isTouchIcon, isPrecomposed: isPrecomposed, width: width, order: order, url: url)
    }

    /// The width of the first size in a `sizes` list (`"16x16 32x32"` is 16); `nil` for `any` or
    /// anything else.
    static func declaredWidth(in sizes: String) -> Int? {
        guard let first = sizes.split(whereSeparator: \.isWhitespace).first,
              let separator = first.firstIndex(where: { $0 == "x" || $0 == "X" })
        else { return nil }
        return Int(first[..<separator])
    }

    private static func isSVG(_ link: HTMLHead.Link) -> Bool {
        if link.type?.contains("svg") == true { return true }
        let path = link.href.split(separator: "?").first.map(String.init) ?? link.href
        return path.lowercased().hasSuffix(".svg")
    }
}
