import Foundation
@testable import PastoCore
import Testing

/// Which title, icon and image a page's tags give. Each expectation is what Link Presentation
/// chose for the same markup (pages served locally to it, macOS 27.2).
struct LinkPageDescriptionTests {
    private let pageURL = URL(string: "https://ejemplo.com/ruta/pagina.html")!

    private func describe(_ head: String) -> LinkPageDescription {
        LinkPageDescription(head: HTMLHead(parsing: Data("<html><head>\(head)</head><body></body></html>".utf8), charset: "utf-8"), url: pageURL)
    }

    private func paths(_ urls: [URL]) -> [String] {
        urls.map { $0.host() == pageURL.host() ? $0.path() : $0.absoluteString }
    }

    // MARK: Title

    @Test func openGraphComesBeforeTwitterAndTwitterBeforeTheTitle() {
        let all = #"<title>Título</title><meta property="og:title" content="OG"><meta name="twitter:title" content="Twitter">"#
        #expect(describe(all).title == "OG")
        #expect(describe(#"<title>Título</title><meta name="twitter:title" content="Twitter">"#).title == "Twitter")
        #expect(describe("<title>Título</title>").title == "Título")
        // Either attribute names the key.
        #expect(describe(#"<title>Título</title><meta name="og:title" content="Por nombre">"#).title == "Por nombre")
        // The first of two counts.
        #expect(describe(#"<meta property="og:title" content="Uno"><meta property="og:title" content="Dos">"#).title == "Uno")
    }

    @Test func anEmptyTagDoesNotCount() {
        #expect(describe(#"<title>Título</title><meta property="og:title" content="  ">"#).title == "Título")
        #expect(describe("<title> \n </title>").title == nil)
        #expect(describe(#"<meta name="description" content="Sin título"><meta property="og:site_name" content="Sitio">"#).title == nil)
    }

    @Test func theTitleIsTidiedAsADocumentTitleAndATagOnlyTrimmed() {
        let title = "<title>\n   Caf&eacute; &amp;  T&#233;\t&#x1F600; &mdash; x &nbsp;y &lt;b&gt; &unknown; &amp\n</title>"
        #expect(describe(title).title == "Café & Té 😀 — x \u{A0}y <b> &unknown; &")
        #expect(describe("<title>A<b>negrita</b>  y   más</title>").title == "A<b>negrita</b> y más")
        let tag = "<meta property=\"og:title\" content=\"  OG &amp; &quot;comillas&quot;\n  dos  \">"
        #expect(describe(tag).title == "OG & \"comillas\"\n  dos")
    }

    @Test(arguments: [
        // On localtest.me, as Link Presentation answered.
        ("Foo | Localtest", "Foo"),
        ("Localtest - Foo", "Foo"),
        ("Local Test | Foo", "Foo"),
        ("Foo – Localtest", "Foo"),
        ("Foo — Localtest", "Foo"),
        ("Foo : Localtest", "Foo"),
        ("Foo :: Localtest", "Foo :"),
        ("Foo » Localtest", "Foo"),
        ("Foo - Localtest.me", "Foo"),
        ("Foo - www.localtest.me", "Foo"),
        ("Foo - Localtést!", "Foo"),
        ("Foo | Localtes", "Foo"),
        ("Foo | The Localtest", "Foo"),
        ("Foo | Localtest Online", "Foo"),
        ("Foo - Bar | Localtest", "Foo - Bar"),
        ("Foo – Bar: Localtest", "Foo – Bar"),
        // Kept whole.
        ("Localtest", "Localtest"),
        ("Foo · Localtest", "Foo · Localtest"),
        ("Foo|Localtest", "Foo|Localtest"),
        ("Foo:Localtest", "Foo:Localtest"),
        ("Foo / Localtest", "Foo / Localtest"),
        ("Foo | Bar | Localtest", "Foo | Bar | Localtest"),
        ("Foo | Local", "Foo | Local"),
        ("Foo | Localtest Abcdefgh", "Foo | Localtest Abcdefgh"),
        ("Foo - Ycombinator", "Foo - Ycombinator"),
        ("Foo - ycombinator.localtest.me", "Foo - ycombinator.localtest.me"),
    ])
    func theSitesOwnNameComesOffTheTitle(title: String, expected: String) {
        #expect(LinkTitleSiteName.removed(from: title, host: "ycombinator.localtest.me") == expected)
    }

    @Test func theSiteIsItsRegistrableDomain() {
        #expect(LinkTitleSiteName.removed(from: "Y Combinator | Hacker News", host: "news.ycombinator.com") == "Hacker News")
        #expect(LinkTitleSiteName.removed(from: "GitHub - swiftlang/swift: The Swift Programming Language", host: "github.com") == "swiftlang/swift: The Swift Programming Language")
        #expect(LinkTitleSiteName.removed(from: "Madrid - Wikipedia, la enciclopedia libre", host: "es.wikipedia.org") == "Madrid - Wikipedia, la enciclopedia libre")
        #expect(LinkTitleSiteName.removed(from: "Noticias - BBC News Mundo", host: "www.bbc.com") == "Noticias - BBC News Mundo")
        #expect(LinkTitleSiteName.removed(from: "Portada | BBC", host: "www.bbc.co.uk") == "Portada")
        #expect(LinkTitleSiteName.removed(from: "Hola | Co", host: "www.bbc.co.uk") == "Hola | Co")
        #expect(LinkTitleSiteName.removed(from: "Inicio | 192", host: "192.168.1.1") == "Inicio | 192")
        // Open Graph titles too.
        #expect(describe(#"<meta property="og:title" content="Ejemplo - Artículo">"#).title == "Artículo")
    }

    // MARK: Icon

    @Test func appleTouchIconsComeFirstThenTheLargestDeclared() {
        let page = describe("""
        <link rel="icon" sizes="16x16" href="/i16.png"><link rel="icon" sizes="32x32" href="/i32.png">
        <link rel="apple-touch-icon" sizes="180x180" href="/a180.png"><link rel="shortcut icon" href="/f.ico">
        <link rel="mask-icon" href="/mask.svg"><link rel="icon" sizes="512x512" href="/i512.png">
        """)

        #expect(paths(page.iconURLs) == [
            "/a180.png", "/i512.png", "/i32.png", "/i16.png", "/f.ico",
            "/apple-touch-icon-precomposed.png",
        ])
    }

    @Test func theFirstSizeListedIsTheWidthAndWithoutOneTheOrderOfThePageDecides() {
        #expect(paths(describe(#"<link rel="icon" sizes="16x16 96x96" href="/a.png"><link rel="icon" sizes="32x32" href="/b.png">"#).iconURLs).prefix(2) == ["/b.png", "/a.png"])
        #expect(paths(describe(#"<link rel="icon" sizes="16x96" href="/a.png"><link rel="icon" sizes="32x32" href="/b.png">"#).iconURLs).prefix(2) == ["/b.png", "/a.png"])
        #expect(paths(describe(#"<link rel="icon" sizes="any" href="/a.png"><link rel="icon" sizes="16x16" href="/b.png">"#).iconURLs).prefix(2) == ["/b.png", "/a.png"])
        #expect(paths(describe(#"<link rel="icon" href="/a.png"><link rel="icon" href="/b.png">"#).iconURLs).prefix(2) == ["/a.png", "/b.png"])
    }

    @Test func anAppleTouchIconWithoutSizesCountsAsSixtyPixels() {
        let declaredSmaller = #"<link rel="apple-touch-icon" sizes="57x57" href="/a57.png"><link rel="apple-touch-icon" href="/sin.png">"#
        #expect(paths(describe(declaredSmaller).iconURLs).prefix(2) == ["/sin.png", "/a57.png"])
        let declaredSame = #"<link rel="apple-touch-icon" sizes="60x60" href="/a60.png"><link rel="apple-touch-icon" href="/sin.png">"#
        #expect(paths(describe(declaredSame).iconURLs).prefix(2) == ["/a60.png", "/sin.png"])
        let precomposed = #"<link rel="apple-touch-icon" sizes="57x57" href="/a.png"><link rel="apple-touch-icon-precomposed" sizes="57x57" href="/p.png">"#
        #expect(paths(describe(precomposed).iconURLs).prefix(2) == ["/p.png", "/a.png"])
    }

    @Test func iconsResolveAgainstTheBaseAndSVGIconsAreSkipped() {
        let page = describe("""
        <base href="https://cdn.ejemplo.com/static/"><link rel="icon" href="i64.png">
        <link rel="icon" type="image/svg+xml" sizes="any" href="/icon.svg"><link rel="icon" href="/otra.svg?v=2">
        """)

        #expect(page.iconURLs.map(\.absoluteString) == [
            "https://cdn.ejemplo.com/static/i64.png",
            "https://ejemplo.com/apple-touch-icon-precomposed.png",
            "https://ejemplo.com/apple-touch-icon.png",
            "https://ejemplo.com/favicon.ico",
        ])
    }

    @Test func onlyTheExactRelValuesAreIcons() {
        let page = describe("""
        <link rel="alternate icon" href="/alt.png"><link rel="icon shortcut" href="/rev.png">
        <link rel="apple-touch-icon icon" href="/mix.png"><link rel="SHORTCUT ICON" href="/ok.ico"><link rel="Apple-Touch-Icon" href="/ok.png">
        """)

        #expect(paths(page.iconURLs).prefix(2) == ["/ok.png", "/ok.ico"])
        #expect(!paths(page.iconURLs).contains("/alt.png"))
    }

    @Test func aProfilePictureOnXOrRedditIsTheIconAndNotTheImage() throws {
        let post = describe("""
        <link rel="apple-touch-icon" href="/touch.png">
        <meta property="og:image" content="https://pbs.twimg.com/profile_images/1/abc_400x400.jpg">
        """)
        #expect(post.iconURLs.first?.absoluteString == "https://pbs.twimg.com/profile_images/1/abc_400x400.jpg")
        #expect(paths(post.iconURLs).dropFirst().first == "/touch.png")
        #expect(post.imageURLs.isEmpty)

        let subreddit = describe(#"<meta property="og:image" content="https://www.redditstatic.com/shreddit/assets/favicon/192x192.png">"#)
        #expect(subreddit.iconURLs.first?.host() == "www.redditstatic.com")
        #expect(subreddit.imageURLs.isEmpty)

        // A profile's banner, the same picture elsewhere, or the picture only second: an image.
        for head in [
            #"<meta name="twitter:image" content="https://pbs.twimg.com/profile_banners/12/1742427520"><meta property="og:image" content="https://pbs.twimg.com/profile_images/1/a.jpg">"#,
            #"<meta property="og:image" content="https://ejemplo.com/profile_images/1/a.jpg">"#,
            #"<meta property="og:image" content="/foto.png"><meta property="og:image" content="https://pbs.twimg.com/profile_images/1/a.jpg">"#,
        ] {
            #expect(!describe(head).imageURLs.isEmpty)
        }
    }

    @Test func iconsInTheBodyAreNotIcons() {
        // YouTube's: a `<div>` early on ends the head, its icon links come long after.
        let page = describe(#"<link rel="icon" sizes="16x16" href="/temprano.png"><div></div><link rel="icon" sizes="144x144" href="/tarde.png">"#)

        #expect(paths(page.iconURLs).prefix(2) == ["/temprano.png", "/apple-touch-icon-precomposed.png"])
    }

    @Test func withoutIconTagsTheUsualPlacesAreTried() {
        #expect(describe("<title>x</title>").iconURLs.map(\.absoluteString) == [
            "https://ejemplo.com/apple-touch-icon-precomposed.png",
            "https://ejemplo.com/apple-touch-icon.png",
            "https://ejemplo.com/favicon.ico",
        ])
    }

    @Test func undeclaredIconsAreLookedForWhereTheLinkPointedBeforeAnyRedirect() throws {
        let head = HTMLHead(parsing: Data(#"<link rel="icon" href="/declarado.png">"#.utf8), charset: nil)
        let description = LinkPageDescription(
            head: head,
            url: try #require(URL(string: "https://www.apple.com/es/")),
            requestedURL: URL(string: "https://apple.co/3wSFfRY")
        )

        #expect(description.iconURLs.map(\.absoluteString) == [
            "https://www.apple.com/declarado.png",
            "https://apple.co/apple-touch-icon-precomposed.png",
            "https://apple.co/apple-touch-icon.png",
            "https://apple.co/favicon.ico",
        ])
    }

    @Test func onlySoManyIconsAreTried() {
        let many = (1...20).map { #"<link rel="icon" sizes="\#($0)x\#($0)" href="/\#($0).png">"# }.joined()
        #expect(describe(many).iconURLs.count == LinkPageDescription.maximumIconCandidates)
    }

    // MARK: Image

    @Test func theFamilyOfTheFirstImageTagWins() {
        #expect(paths(describe(#"<meta property="og:image" content="/og.png"><meta name="twitter:image" content="/tw.png">"#).imageURLs) == ["/og.png"])
        #expect(paths(describe(#"<meta name="twitter:image" content="/tw.png"><meta property="og:image" content="/og.png">"#).imageURLs) == ["/tw.png"])
        #expect(paths(describe(#"<meta itemprop="image" content="/ip.png"><meta property="og:image" content="/og.png">"#).imageURLs) == ["/og.png"])
        #expect(paths(describe(#"<meta itemprop="image" content="/ip.png">"#).imageURLs) == ["/ip.png"])
        // `twitter:image:src` is not read; `og:image:url` and `property="twitter:image"` are.
        #expect(paths(describe(#"<meta name="twitter:image:src" content="/src.png">"#).imageURLs) == [])
        #expect(paths(describe(#"<meta property="og:image:url" content="/url.png">"#).imageURLs) == ["/url.png"])
        #expect(paths(describe(#"<meta property="twitter:image" content="/tw.png">"#).imageURLs) == ["/tw.png"])
    }

    @Test func aSecureAddressReplacesTheImageJustBeforeIt() {
        let replaced = #"<meta property="og:image" content="/a.png"><meta property="og:description" content="x"><meta property="og:image:secure_url" content="/s.png">"#
        #expect(paths(describe(replaced).imageURLs) == ["/s.png"])
        let before = #"<meta property="og:image:secure_url" content="/s.png"><meta property="og:image" content="/a.png">"#
        #expect(paths(describe(before).imageURLs) == ["/s.png"])
        // Another image tag in between makes it an image of its own.
        let apart = #"<meta property="og:image" content="/a.png"><meta property="og:image:width" content="1200"><meta property="og:image:secure_url" content="/s.png">"#
        #expect(paths(describe(apart).imageURLs) == ["/a.png", "/s.png"])
        let second = #"<meta property="og:image" content="/a.png"><meta property="og:image" content="/b.png"><meta property="og:image:secure_url" content="/s.png">"#
        #expect(paths(describe(second).imageURLs) == ["/a.png", "/s.png"])
    }

    @Test func aRepeatedImageIsTriedOnce() {
        let twice = #"<meta property="og:image" content="/a.png"><meta property="og:image" content="https://ejemplo.com/a.png"><meta property="og:image" content="/b.png">"#
        #expect(paths(describe(twice).imageURLs) == ["/a.png", "/b.png"])
    }

    @Test func imagesResolveAgainstThePageNotItsBase() {
        let page = describe(#"<base href="/sub/"><meta property="og:image" content="  g600.png  "><meta property="og:image" content="//cdn.ejemplo.com/x.png"><meta property="og:image" content="javascript:alert(1)">"#)

        #expect(page.imageURLs.map(\.absoluteString) == ["https://ejemplo.com/ruta/g600.png", "https://cdn.ejemplo.com/x.png"])
    }
}
