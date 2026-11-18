import Foundation

/// The page images Link Presentation shows as the link's icon instead of its image: a profile
/// picture on X and a community's icon on Reddit — a post's author, a subreddit. As of macOS
/// 27.2, it goes by the image's address alone, whatever the page, its tags or the image's size;
/// the same picture under another address stays an image.
/// So an X post shows its author's picture as icon and no image, while an X profile, whose
/// first image is its banner, keeps it as image.
enum LinkProfilePicture {
    /// The addresses, by host and the start of their path.
    private static let addresses = [
        ("pbs.twimg.com", "/profile_images/"),
        ("www.redditstatic.com", "/shreddit/assets/favicon/"),
    ]

    static func isProfilePicture(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let path = url.path()
        return addresses.contains { host == $0.0 && path.hasPrefix($0.1) }
    }
}
