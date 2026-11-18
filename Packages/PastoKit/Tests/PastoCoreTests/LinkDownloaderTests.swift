import Foundation
@testable import PastoCore
import Testing

/// Link downloads through `URLSession` against `FakeWebServer`: which redirects are followed,
/// where a page and an image stop, and what the requests carry. Nothing reaches the network.
@Suite(.timeLimit(.minutes(1)))
struct LinkDownloaderTests {
    private let page = Data("<html><head><title>Página</title></head><body>hola</body></html>".utf8)

    private func downloadPage(_ address: String, with downloader: LinkDownloader = FakeWebServer.downloader()) async throws -> Result<LinkDownload, LinkDownloadFailure> {
        await downloader.download(try #require(URL(string: address)), accept: LinkDownloader.pageAccept, plan: SystemLinkMetadataProvider.pagePlan(for:))
    }

    @Test(arguments: [
        ("http://127.0.0.1/admin", "127.0.0.1"),
        ("http://localhost:8080/", "localhost"),
        ("http://192.168.1.1/reboot", "192.168.1.1"),
        ("http://169.254.169.254/latest/meta-data", "169.254.169.254"),
        ("https://[::1]/", "::1"),
        ("file:///etc/passwd", ""),
    ])
    func aRedirectIntoThisMacOrTheLocalNetworkIsNotFollowed(target: String, targetHost: String) async throws {
        let host = "redirect-\(target.filter { $0.isLetter || $0.isNumber }).example"
        FakeWebServer.route("https://\(host)/", .redirect(location: target))

        let result = try await downloadPage("https://\(host)/")

        #expect(result == .failure(.redirectRefused))
        #expect(FakeWebServer.requests(toHost: targetHost).isEmpty)
        #expect(FakeWebServer.requests(startingWith: "file:").isEmpty)
    }

    @Test func aRedirectToANameThatResolvesIntoTheLocalNetworkIsNotFollowed() async throws {
        FakeWebServer.route("https://rebinding.example/", .redirect(location: "https://intranet-alias.example/"))
        // The name looks public; its addresses are not.
        let downloader = FakeWebServer.downloader { url in
            LinkFetchPolicy.allowsFetching(url) && url.host() != "intranet-alias.example"
        }

        let result = try await downloadPage("https://rebinding.example/", with: downloader)

        #expect(result == .failure(.redirectRefused))
        #expect(FakeWebServer.requests(toHost: "intranet-alias.example").isEmpty)
    }

    @Test func aRedirectToAPublicPageIsFollowedAndItsAddressKept() async throws {
        FakeWebServer.route("https://short.example/x", .redirect(status: 301, location: "https://public-target.example/articulo"))
        FakeWebServer.route("https://public-target.example/articulo", .page(body: page))

        let download = try await downloadPage("https://short.example/x").get()

        #expect(download.url.absoluteString == "https://public-target.example/articulo")
        #expect(download.mimeType == "text/html")
        #expect(download.charset == "utf-8")
        #expect(download.data == page)
    }

    @Test func anAddressIsAskedAsItComes() async throws {
        // What App Transport Security makes of plain HTTP is the system's to decide, as for Link
        // Presentation; this session asks what it is given.
        FakeWebServer.route("http://plain.example/a", .redirect(location: "http://plain-target.example/b"))
        FakeWebServer.route("http://plain-target.example/b", .page(body: page))

        let download = try await downloadPage("http://plain.example/a").get()

        #expect(download.url.absoluteString == "http://plain-target.example/b")
        #expect(FakeWebServer.requests(startingWith: "https://plain").isEmpty)
    }

    @Test func aChainOfRedirectsStopsAfterTheMaximum() async throws {
        for hop in 0...LinkDownloader.maximumRedirects + 1 {
            FakeWebServer.route("https://loop.example/\(hop)", .redirect(location: "/\(hop + 1)"))
        }

        let result = try await downloadPage("https://loop.example/0")

        #expect(result == .failure(.tooManyRedirects))
        #expect(FakeWebServer.requests(startingWith: "https://loop.example/").count == LinkDownloader.maximumRedirects + 1)
    }

    @Test func anAddressThePolicyRefusesIsNeverRequested() async throws {
        let result = try await downloadPage("http://192.168.1.1/")

        #expect(result == .failure(.notAllowed))
        #expect(FakeWebServer.requests(toHost: "192.168.1.1").isEmpty)
    }

    @Test func aPageThatDoesNotEndIsCutAtTheLimit() async throws {
        let url = "https://huge.example/"
        // 50 MB of a page that never closes its head.
        FakeWebServer.route(url, .stream(
            headers: ["Content-Type": "text/html"], length: 50 * 1024 * 1024, chunk: 256 * 1024,
            declaresLength: true, prefix: Data("<html><head><title>Huge</title>".utf8)
        ))

        let download = try await downloadPage(url).get()

        #expect(download.isTruncated)
        #expect(download.data.count == SystemLinkMetadataProvider.pageByteLimit)
        #expect(download.data.starts(with: Data("<html><head><title>Huge".utf8)))
        // The transfer stopped soon after the limit, far from the 50 MB.
        #expect(FakeWebServer.streamedBytes(of: url) < SystemLinkMetadataProvider.pageByteLimit + 4 * 256 * 1024)
    }

    @Test func aPageStopsAsSoonAsItsHeadIsIn() async throws {
        let url = "https://long-body.example/"
        let head = Data("<html><head><title>Corta</title><script>var s = '</head>';</script></head><body>".utf8)
        FakeWebServer.route(url, .stream(
            headers: ["Content-Type": "text/html"], length: 20 * 1024 * 1024, chunk: 16 * 1024,
            declaresLength: false, prefix: head
        ))

        let download = try await downloadPage(url).get()

        // The `</head>` in the script string did not stop it before the real one, and the real
        // one did, a chunk or so later.
        #expect(download.data.starts(with: head))
        #expect(download.data.count <= 64 * 1024)
        #expect(!download.isTruncated)
        #expect(FakeWebServer.streamedBytes(of: url) < 20 * 1024 * 1024 / 2)
    }

    @Test func anImageOverTheLimitIsDroppedWholeWhetherOrNotItSaysItsLength() async throws {
        for declaresLength in [true, false] {
            let url = "https://big-image-\(declaresLength).example/a.png"
            FakeWebServer.route(url, .stream(
                headers: ["Content-Type": "image/png"], length: SystemLinkMetadataProvider.imageByteLimit + 1, chunk: 1024 * 1024,
                declaresLength: declaresLength, prefix: Data()
            ))

            let result = await FakeWebServer.downloader().download(
                try #require(URL(string: url)), accept: LinkDownloader.imageAccept, plan: SystemLinkMetadataProvider.imagePlan(for:)
            )

            #expect(result == .failure(.tooLarge))
        }
        // A declared length is refused with the headers, before the body flows.
        #expect(FakeWebServer.streamedBytes(of: "https://big-image-true.example/a.png") < 4 * 1024 * 1024)
    }

    @Test func aPageWhereAnImageShouldBeIsNotDownloaded() async throws {
        FakeWebServer.route("https://soft-404.example/favicon.ico", .page(body: page))

        let result = await FakeWebServer.downloader().download(
            try #require(URL(string: "https://soft-404.example/favicon.ico")),
            accept: LinkDownloader.imageAccept, plan: SystemLinkMetadataProvider.imagePlan(for:)
        )

        #expect(result == .failure(.unwantedContent))
    }

    @Test func ofALinkToAFileOnlyTheHeadersAreRead() async throws {
        let url = "https://files.example/video.mp4"
        FakeWebServer.route(url, .stream(
            headers: ["Content-Type": "video/mp4"], length: 10 * 1024 * 1024, chunk: 64 * 1024,
            declaresLength: true, prefix: Data()
        ))

        let download = try await downloadPage(url).get()

        #expect(download.mimeType == "video/mp4")
        #expect(download.data.isEmpty)
    }

    @Test func anErrorPageGivesNothing() async throws {
        FakeWebServer.route("https://missing.example/", .page(status: 404, body: page))

        #expect(try await downloadPage("https://missing.example/") == .failure(.status(404)))
    }

    @Test func requestsCarryLinkPresentationsAgentAndNothingOfTheUsers() async throws {
        FakeWebServer.route("https://cookies.example/1", .page(
            headers: ["Content-Type": "text/html", "Set-Cookie": "session=secreto; Path=/"], body: page
        ))
        FakeWebServer.route("https://cookies.example/2", .page(body: page))

        _ = try await downloadPage("https://usuario:clave@cookies.example/1")
        _ = try await downloadPage("https://cookies.example/2")

        let requests = FakeWebServer.requests(startingWith: "https://cookies.example/")
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "User-Agent") == LinkDownloader.userAgent)
            #expect(request.value(forHTTPHeaderField: "Accept") == LinkDownloader.pageAccept)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.url?.user() == nil)
        }
    }
}
