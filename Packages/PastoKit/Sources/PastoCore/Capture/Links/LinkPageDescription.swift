import Foundation

/// What a page offers its link card, chosen the way Link Presentation chooses (as of macOS
/// 27.2): the title, and where the icon and the representative image may be, best first. The
/// first of each that downloads and decodes wins.
struct LinkPageDescription: Equatable {
    var title: String?
    var iconURLs: [URL]
    var imageURLs: [URL]

    /// At most this many places are tried for each: a page cannot make Pasto fetch dozens.
    static let maximumIconCandidates = 6
    static let maximumImageCandidates = 3

    /// - Parameters:
    ///   - url: The page's address after redirects: titles and the page's own addresses go by it.
    ///   - requestedURL: The address asked for. Link Presentation looks for the icons nobody
    ///     declares (`/favicon.ico`…) there, before the page — and any redirect — arrives:
    ///     apple.co's own icon for a short link to apple.com.
    init(head: HTMLHead, url: URL, requestedURL: URL? = nil) {
        title = Self.title(in: head, host: url.host())
        let icons = LinkIconChoice.candidates(in: head, pageURL: url, fallbackURL: requestedURL ?? url)
        let images = Self.imageCandidates(in: head, pageURL: url)
        if let picture = images.first, LinkProfilePicture.isProfilePicture(picture) {
            // Link Presentation's own treatment of these sites: the picture is the icon.
            iconURLs = Array(([picture] + icons).prefix(Self.maximumIconCandidates))
            imageURLs = []
        } else {
            iconURLs = Array(icons.prefix(Self.maximumIconCandidates))
            imageURLs = Array(images.prefix(Self.maximumImageCandidates))
        }
    }

    init(title: String?, iconURLs: [URL], imageURLs: [URL]) {
        self.title = title
        self.iconURLs = iconURLs
        self.imageURLs = imageURLs
    }

    /// `og:title`, else `twitter:title`, trimmed; else the `<title>`, with its runs of white
    /// space made one space, as a browser's `document.title`. An empty one counts as none. The
    /// site's own name comes off whichever it is (`LinkTitleSiteName`).
    static func title(in head: HTMLHead, host: String?) -> String? {
        for key in ["og:title", "twitter:title"] {
            let content = head.metas.lazy
                .filter { $0.isNamed(key) }
                .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let content {
                return LinkTitleSiteName.removed(from: content, host: host)
            }
        }
        guard let title = head.title.map(collapsingHTMLSpace), !title.isEmpty else { return nil }
        return LinkTitleSiteName.removed(from: title, host: host)
    }

    /// `text` without HTML white space at its ends and with each run inside it made one space.
    /// A non-breaking space is not white space here.
    static func collapsingHTMLSpace(_ text: String) -> String {
        text.split(whereSeparator: { "\t\n\u{0C}\r ".contains($0) }).joined(separator: " ")
    }

    /// The page's image candidates. The Open Graph and Twitter tags compete by which comes first
    /// in the page: Link Presentation takes all its images from that family and never falls
    /// back to the other. `itemprop="image"` only counts without either.
    ///
    /// Open Graph images are structured: `og:image:secure_url` replaces the address of the
    /// `og:image` just before it (unless another image tag came between), and an image's
    /// `og:image` can come after its `og:image:secure_url`.
    ///
    /// Addresses resolve against the page's address, not its `<base>`, as Link Presentation does.
    static func imageCandidates(in head: HTMLHead, pageURL: URL) -> [URL] {
        var openGraph: [(url: String?, secureURL: String?)] = []
        var twitter: [String] = []
        var itemprop: [String] = []
        var firstFamily: String?
        var lastImageTagWasAddress = false

        for meta in head.metas {
            let content = meta.content
            if meta.isNamed("og:image") || meta.isNamed("og:image:url") {
                firstFamily = firstFamily ?? "og"
                if let last = openGraph.indices.last, openGraph[last].url == nil {
                    openGraph[last].url = content
                } else {
                    openGraph.append((content, nil))
                }
                lastImageTagWasAddress = true
            } else if meta.isNamed("og:image:secure_url") {
                firstFamily = firstFamily ?? "og"
                if lastImageTagWasAddress, let last = openGraph.indices.last, openGraph[last].secureURL == nil {
                    openGraph[last].secureURL = content
                } else {
                    openGraph.append((nil, content))
                }
                lastImageTagWasAddress = false
            } else if meta.isNamed("twitter:image") {
                firstFamily = firstFamily ?? "twitter"
                twitter.append(content)
                lastImageTagWasAddress = false
            } else if [meta.property, meta.name].contains(where: { $0?.hasPrefix("og:image:") == true }) {
                lastImageTagWasAddress = false
            } else if meta.itemprop == "image" {
                itemprop.append(content)
            }
        }

        let addresses: [String] = switch firstFamily {
        case "og": openGraph.compactMap { $0.secureURL ?? $0.url }
        case "twitter": twitter
        default: itemprop
        }
        // A page that repeats its tags (YouTube's head has them twice) gets each image tried once.
        var seen = Set<URL>()
        return addresses.compactMap { resolved($0, against: pageURL) }.filter { seen.insert($0).inserted }
    }

    /// An address as written in a page, made absolute: trimmed, without the tabs and line breaks
    /// a browser ignores, and only if it is a web address.
    static func resolved(_ address: String, against base: URL) -> URL? {
        let cleaned = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0 != "\t" && $0 != "\n" && $0 != "\r" }
        guard !cleaned.isEmpty, let url = URL(string: cleaned, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}
