import CoreGraphics
import Foundation
import ImageIO
@testable import PastoCore
import Testing
import UniformTypeIdentifiers

/// The whole lookup against `FakeWebServer`: page, icon and image, each under the same rules.
@Suite(.timeLimit(.minutes(1)))
struct SystemLinkMetadataProviderTests {
    private let provider = SystemLinkMetadataProvider(downloader: FakeWebServer.downloader())

    /// A PNG of one colour, with a square of another unless `plain`.
    private func png(width: Int, height: Int, plain: Bool = false) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if !plain {
            context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 4, height: height / 4))
        }
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func lookUp(_ address: String) async throws -> LinkMetadata? {
        await provider.metadata(for: try #require(URL(string: address)))
    }

    private func pixelSize(of data: Data?) throws -> CGSize {
        let data = try #require(data)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return CGSize(width: properties[kCGImagePropertyPixelWidth] as? Int ?? 0, height: properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    private func image(_ data: Data) -> FakeWebServer.Route {
        .page(headers: ["Content-Type": "image/png"], body: data)
    }

    @Test func aPageGivesItsTitleIconAndImage() async throws {
        let html = """
        <html><head><title>Título</title><meta property="og:title" content="Artículo &amp; más">
        <link rel="apple-touch-icon" href="/falta.png"><link rel="icon" sizes="32x32" href="/icono.png">
        <meta property="og:image" content="https://imagenes.example/portada.png"></head><body></body></html>
        """
        FakeWebServer.route("https://pagina.example/articulo", .page(body: Data(html.utf8)))
        FakeWebServer.route("https://pagina.example/icono.png", image(try png(width: 256, height: 256)))
        FakeWebServer.route("https://imagenes.example/portada.png", image(try png(width: 2400, height: 1200)))

        let metadata = try #require(try await lookUp("https://pagina.example/articulo"))

        #expect(metadata.title == "Artículo & más")
        // The apple-touch icon is missing, so the next one is used, reduced to 128 × 128 pixels.
        #expect(try pixelSize(of: metadata.iconData) == CGSize(width: 128, height: 128))
        #expect(try pixelSize(of: metadata.imageData).width <= 1024)
    }

    @Test func aFirstImageOfASingleColourMeansNoImage() async throws {
        let html = #"<head><title>Relleno</title><meta property="og:image" content="/liso.png"><meta property="og:image" content="/foto.png"></head>"#
        FakeWebServer.route("https://relleno.example/", .page(body: Data(html.utf8)))
        FakeWebServer.route("https://relleno.example/liso.png", image(try png(width: 1200, height: 630, plain: true)))
        FakeWebServer.route("https://relleno.example/foto.png", image(try png(width: 1200, height: 630)))

        let page = try #require(try await lookUp("https://relleno.example/"))

        #expect(page.imageData == nil)
        #expect(FakeWebServer.requests(startingWith: "https://relleno.example/foto.png").isEmpty)
    }

    @Test func anImageThatRedirectsIntoTheLocalNetworkIsLeftOut() async throws {
        let html = #"<head><title>Con trampa</title><meta property="og:image" content="/img"><link rel="icon" href="/ico"></head>"#
        FakeWebServer.route("https://trampa.example/", .page(body: Data(html.utf8)))
        FakeWebServer.route("https://trampa.example/img", .redirect(location: "http://192.168.1.1/camara.jpg"))
        FakeWebServer.route("https://trampa.example/ico", .redirect(location: "http://127.0.0.1:631/printers"))

        let metadata = try #require(try await lookUp("https://trampa.example/"))

        #expect(metadata == LinkMetadata(title: "Con trampa"))
        #expect(FakeWebServer.requests(toHost: "192.168.1.1").isEmpty)
        #expect(FakeWebServer.requests(toHost: "127.0.0.1").isEmpty)
    }

    @Test func aPageThatRedirectsIntoTheLocalNetworkGivesNothing() async throws {
        FakeWebServer.route("https://acortador.example/abc", .redirect(location: "http://10.0.0.1/admin"))

        #expect(try await lookUp("https://acortador.example/abc") == nil)
    }

    @Test func aLinkStraightToAnImageShowsIt() async throws {
        FakeWebServer.route("https://fotos.example/vacaciones/Playa%20Norte.png", image(try png(width: 800, height: 600)))

        let metadata = try #require(try await lookUp("https://fotos.example/vacaciones/Playa%20Norte.png"))

        #expect(metadata.title == "Playa Norte")
        #expect(try pixelSize(of: metadata.iconData) == CGSize(width: 64, height: 64))
        // 512 points at 2× is more than the image has: it keeps its pixels.
        #expect(try pixelSize(of: metadata.imageData) == CGSize(width: 800, height: 600))
    }

    @Test func aLinkToAnotherFileIsNamedButNotDownloaded() async throws {
        FakeWebServer.route("https://docs.example/datos.zip", .page(headers: ["Content-Type": "application/zip"], body: Data("PK".utf8)))

        let metadata = try #require(try await lookUp("https://docs.example/datos.zip"))

        #expect(metadata.title == "datos")
        #expect(metadata.iconData != nil)
        #expect(metadata.imageData == nil)
    }

    @Test func aPDFShowsItsFirstPageAndLeavesNoCopyBehind() async throws {
        // A landscape page, so its shape shows in the thumbnail.
        let pdf = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 800, height: 400)
        let consumer = try #require(CGDataConsumer(data: pdf))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 100, y: 100, width: 200, height: 100))
        context.endPDFPage()
        context.closePDF()
        FakeWebServer.route("https://docs.example/informe.pdf", .page(headers: ["Content-Type": "application/pdf"], body: pdf as Data))

        let metadata = try #require(try await lookUp("https://docs.example/informe.pdf"))

        #expect(metadata.title == "informe")
        #expect(metadata.iconData != nil)
        let page = try pixelSize(of: metadata.imageData)
        #expect(page.width > page.height)
        let folders = try FileManager.default.contentsOfDirectory(atPath: URL.temporaryDirectory.path)
        #expect(!folders.contains { $0.hasPrefix(LinkDocumentThumbnail.folderPrefix) })
    }

    @Test func aResponseWithoutAContentTypeIsReadOnlyIfItLooksLikeHTML() async throws {
        FakeWebServer.route("https://sin-tipo.example/html", .page(headers: [:], body: Data("\n<!DOCTYPE html><title>Sin tipo</title>".utf8)))
        FakeWebServer.route("https://sin-tipo.example/bin", .page(headers: [:], body: Data([0, 1, 2, 3])))

        #expect(try await lookUp("https://sin-tipo.example/html")?.title == "Sin tipo")
        #expect(try await lookUp("https://sin-tipo.example/bin") == nil)
    }

    @Test func runningOutOfTimeGivesNothingEvenWithThePageRead() async throws {
        // As Link Presentation, whose lookup fails when an icon never finishes loading.
        let html = #"<head><title>Lenta</title><link rel="icon" href="/icono.png"></head>"#
        FakeWebServer.route("https://lenta.example/", .page(body: Data(html.utf8)))
        FakeWebServer.route("https://lenta.example/icono.png", .stall(headers: ["Content-Type": "image/png"]))
        let provider = SystemLinkMetadataProvider(downloader: FakeWebServer.downloader(), timeout: .seconds(1))

        let metadata = await provider.metadata(for: try #require(URL(string: "https://lenta.example/")))

        #expect(metadata == nil)
    }

    @Test func aPageWithoutTitleHasNone() async throws {
        FakeWebServer.route("https://sin-titulo.example/", .page(body: Data("<head><meta name=description content=nada></head>".utf8)))

        #expect(try await lookUp("https://sin-titulo.example/") == LinkMetadata())
    }
}
