import Foundation
import ImageIO
import os
import PastoFoundation
import UniformTypeIdentifiers

/// Link metadata — the title, icon and image a link card shows — read from the page itself.
/// Pasto downloads the page with a session of its own rather than asking Link Presentation,
/// because Link Presentation loads it in a web view that follows any redirect — to this Mac or
/// the local network included — and reads pages of any size. The choices follow Link
/// Presentation's (`LinkPageDescription`).
///
/// One fresh request per call, no retries and no sharing of requests in flight; at most
/// `LinkDownloader.timeout` for everything. Only public web addresses are asked, every redirect
/// included, as they come (`http` as App Transport Security allows it, as for Link Presentation
/// in the app), and nothing is kept from a connection that reached a local address after all
/// (`LinkDownloader`, `LinkTransfer`); a page is read up to `pageByteLimit` bytes and only up to
/// its `</head>`; no script runs and no `<meta http-equiv="refresh">` is followed. An icon or
/// image larger than `imageByteLimit` is dropped before it is decoded.
public struct SystemLinkMetadataProvider: LinkMetadataProviding {
    /// The icon is stored no larger than this on its longest side, in pixels.
    static let iconPixelLimit = 128
    /// The image is reduced to fit a square of this side, in points.
    static let imagePointLimit: CGFloat = 512
    /// An icon or image the page hands over larger than this, encoded, is not used.
    static let imageByteLimit = 20 * 1024 * 1024
    /// At most this much of a page is read, decompressed. What a preview needs is in the
    /// `<head>`: the longest of those checked, YouTube's, ends at 1.35 MB (its Open Graph tags
    /// are in the first 3 KB, its icons at 552 KB), and most end within 350 KB. It is also twice
    /// the limit Link Presentation itself applies to a page that declares its length (it refuses
    /// a `Content-Length` over 1 MiB, but reads a page sent in chunks whatever its size).
    static let pageByteLimit = 2 * 1024 * 1024

    private static let log = Log.logger(.pasteboard)

    private let downloader: LinkDownloader
    private let timeout: Duration

    public init() {
        self.init(downloader: LinkDownloader())
    }

    /// `timeout` is `LinkDownloader.timeout` but in tests.
    init(downloader: LinkDownloader, timeout: Duration = .seconds(LinkDownloader.timeout)) {
        self.downloader = downloader
        self.timeout = timeout
    }

    public func metadata(for url: URL) async -> LinkMetadata? {
        await withTaskGroup(of: LinkMetadata??.self) { group in
            group.addTask { .some(await describe(url)) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .none
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if first == nil {
                // As with Link Presentation, out of time means no metadata, even with the page
                // read and only an icon still loading.
                Self.log.info("Link metadata timed out")
            }
            return first ?? nil
        }
    }

    /// Runs in a child task of `metadata(for:)`, away from the caller's actor: parsing and image
    /// decoding never block it.
    private func describe(_ url: URL) async -> LinkMetadata? {
        let page: LinkDownload
        switch await downloader.download(url, accept: LinkDownloader.pageAccept, plan: Self.pagePlan(for:)) {
        case .success(let download):
            page = download
        case .failure(let failure):
            Self.log.info("Link page not read: \(failure.description, privacy: .public)")
            return nil
        }
        if page.isTruncated {
            Self.log.info("Link page cut at \(page.data.count) bytes")
        }

        switch LinkContentKind(mimeType: page.mimeType) {
        case .page:
            return await describePage(page, requestedURL: url)
        case .undeclared:
            guard LinkContentKind.looksLikeHTML(page.data) else {
                Self.log.info("Link page without a content type is not HTML")
                return nil
            }
            return await describePage(page, requestedURL: url)
        case .image:
            return LinkMetadata(
                title: LinkFileIcon.title(of: page.url),
                iconData: LinkFileIcon.png(for: page.url, mimeType: page.mimeType),
                imageData: Self.reducedPageImage(of: page.data).flatMap { LinkPlainImage.isPlain($0) ? nil : $0 }
            )
        case .document:
            let firstPage = await LinkDocumentThumbnail.png(ofPDF: page.data)
            return LinkMetadata(
                title: LinkFileIcon.title(of: page.url),
                iconData: LinkFileIcon.png(for: page.url, mimeType: page.mimeType),
                imageData: firstPage.flatMap(Self.reducedPageImage(of:)).flatMap { LinkPlainImage.isPlain($0) ? nil : $0 }
            )
        case .file:
            return LinkMetadata(
                title: LinkFileIcon.title(of: page.url),
                iconData: LinkFileIcon.png(for: page.url, mimeType: page.mimeType)
            )
        }
    }

    private func describePage(_ page: LinkDownload, requestedURL: URL) async -> LinkMetadata {
        let description = LinkPageDescription(
            head: HTMLHead(parsing: page.data, charset: page.charset),
            url: page.url,
            requestedURL: LinkDownloader.withoutCredentials(requestedURL)
        )
        async let icon = firstImage(at: description.iconURLs, reduce: Self.reducedIcon(of:))
        async let image = firstImage(at: description.imageURLs, reduce: Self.reducedPageImage(of:), dropsPlain: true)
        return await LinkMetadata(title: description.title, iconData: icon, imageData: image)
    }

    /// A page's image as Link Presentation would hand it over (`LinkImageLimit`), reduced.
    private static func reducedPageImage(of data: Data) -> Data? {
        LinkImageLimit.limited(data).flatMap(reducedImage(of:))
    }

    /// The first of `urls` that downloads and decodes, reduced. One after the other, so that a
    /// page with several candidates costs one download when the best one works. With
    /// `dropsPlain`, a first image of a single colour means no image (`LinkPlainImage`).
    private func firstImage(at urls: [URL], reduce: (Data) -> Data?, dropsPlain: Bool = false) async -> Data? {
        for url in urls {
            guard !Task.isCancelled else { return nil }
            switch await downloader.download(url, accept: LinkDownloader.imageAccept, plan: Self.imagePlan(for:)) {
            case .success(let download):
                if let reduced = reduce(download.data) {
                    return dropsPlain && LinkPlainImage.isPlain(reduced) ? nil : reduced
                }
                Self.log.debug("Link image of \(download.data.count) bytes not decodable")
            case .failure(let failure):
                Self.log.debug("Link image not read: \(failure.description, privacy: .public)")
            }
        }
        return nil
    }

    /// A page is kept up to `pageByteLimit` and its `</head>`; a link straight to an image or a
    /// PDF is downloaded like an image; of anything else only the headers are needed.
    @Sendable
    static func pagePlan(for response: HTTPURLResponse) -> LinkDownloadPlan? {
        switch LinkContentKind(mimeType: LinkDownload.mimeType(in: response.value(forHTTPHeaderField: "Content-Type"))) {
        case .page, .undeclared:
            LinkDownloadPlan(byteLimit: pageByteLimit, keepsPrefix: true, endsWithHead: true)
        case .image, .document:
            LinkDownloadPlan(byteLimit: imageByteLimit, keepsPrefix: false)
        case .file:
            LinkDownloadPlan(byteLimit: 0, keepsPrefix: true)
        }
    }

    /// Icons and images: whole, up to `imageByteLimit`. A page where an image should be — the
    /// error page a site serves for a missing `/favicon.ico` — is not downloaded.
    @Sendable
    static func imagePlan(for response: HTTPURLResponse) -> LinkDownloadPlan? {
        guard LinkContentKind(mimeType: LinkDownload.mimeType(in: response.value(forHTTPHeaderField: "Content-Type"))) != .page else {
            return nil
        }
        return LinkDownloadPlan(byteLimit: imageByteLimit, keepsPrefix: false)
    }

    /// The icon as PNG, scaled down — never up — so that its longest side is at most
    /// `iconPixelLimit` pixels.
    static func reducedIcon(of data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return reducedPNG(of: source, pixelLimit: iconPixelLimit)
    }

    /// The image as PNG, fitted into an `imagePointLimit` square by its size in points, like
    /// the thumbnail of an image item.
    static func reducedImage(of data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0
        else { return nil }
        let pixelSize = ImageFitting.pixelSize(
            fitting: CGSize(width: imagePointLimit, height: imagePointLimit),
            pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
            pointSize: ImageFitting.pointSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight, properties: properties)
        )
        return reducedPNG(of: source, pixelLimit: Int(max(pixelSize.width, pixelSize.height)))
    }

    private static func reducedPNG(of source: CGImageSource, pixelLimit: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelLimit,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
