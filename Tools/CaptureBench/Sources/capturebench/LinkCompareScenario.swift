import Darwin
import Foundation
import ImageIO
import LinkPresentation
import PastoCore
import UniformTypeIdentifiers

/// Asks Link Presentation and Pasto's own metadata reader about the same links, and prints what
/// each gives a link card: title, icon, image, time and bytes.
///
/// Bytes are what the network interfaces received while each lookup ran: headers, TLS and any
/// background traffic of the Mac included (the line above the table says how much that is).
/// The two run one after the other, in alternating order, so that neither always finds the
/// servers' caches warm.
enum LinkCompareScenario {
    /// Varied public pages: shops, news, video, code, encyclopedias, social sites, a PDF, an
    /// image, a plain-HTTP address that redirects to HTTPS, sites without HTTPS and two short
    /// links.
    static let defaultURLs = [
        "https://www.apple.com/es/",
        "https://elpais.com/babelia/2026-11-17/diego-del-alcazar-escritor-y-empresario-la-felicidad-impostada-es-un-sintoma-muy-preocupante-de-nuestro-tiempo.html",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://github.com/apple/swift",
        "https://es.wikipedia.org/wiki/Madrid",
        "https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta",
        "https://www.amazon.es/dp/8497592204",
        "https://apps.apple.com/es/app/pages/id361309726",
        "https://x.com/jack/status/20",
        "https://stackoverflow.com/questions/11227809/why-is-processing-a-sorted-array-faster-than-processing-an-unsorted-array",
        "https://ma.tt/",
        "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf",
        "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg",
        "http://www.boe.es/",
        // Sites that do not speak HTTPS, or barely.
        "http://httpforever.com/",
        "http://neverssl.com/",
        "http://info.cern.ch/",
        "https://apple.co/3wSFfRY",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://www.reddit.com/r/apple/",
        "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT",
        "https://news.ycombinator.com/item?id=1",
        "https://www.bbc.com/mundo",
        "https://vimeo.com/76979871",
        "https://www.instagram.com/nasa/",
        "https://www.swift.org/",
        "https://www.nytimes.com/",
        "https://www.iana.org/help/example-domains",
    ]

    /// What one reader gave for one link.
    struct Outcome {
        var title: String?
        var iconSide: Int?
        var imageSize: CGSize?
        var failed: Bool
        var milliseconds: Double
        var bytes: Int
    }

    @MainActor
    static func run(urlsFile: String?) async throws {
        let addresses: [String]
        if let urlsFile {
            addresses = try String(contentsOfFile: urlsFile, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        } else {
            addresses = defaultURLs
        }
        let urls = try addresses.map { address in
            guard let url = URL(string: address) else { throw BenchError("not a URL: \(address)") }
            return url
        }

        let background = try await backgroundBytesPerSecond()
        print("Background traffic: \(Int(background / 1024)) KB/s (included in every byte count below)\n")
        print("| # | Link | Title (LP → new) | = | Icon LP/new | Image LP/new | ms LP | ms new | KB LP | KB new |")
        print("|---|---|---|---|---|---|---|---|---|---|")

        let provider = SystemLinkMetadataProvider()
        var rows: [(url: URL, old: Outcome, new: Outcome)] = []
        for (index, url) in urls.enumerated() {
            var old: Outcome?
            var new: Outcome?
            // Alternate which goes first.
            for turn in index.isMultiple(of: 2) ? [0, 1] : [1, 0] {
                if turn == 0 {
                    old = await measure { await LegacyLinkMetadataProvider.metadata(for: url) }
                } else {
                    new = await measure { await provider.metadata(for: url) }
                }
            }
            guard let old, let new else { continue }
            rows.append((url, old, new))
            print(row(index + 1, url, old, new))
        }
        summarize(rows)
    }

    /// Runs one lookup and measures it; waits a moment after, so that traffic still in flight
    /// counts for the lookup that caused it.
    @MainActor
    private static func measure(_ lookup: @MainActor () async -> PastoCore.LinkMetadata?) async -> Outcome {
        let before = InterfaceCounter.receivedBytes()
        let start = ContinuousClock.now
        let metadata = await lookup()
        let elapsed = ContinuousClock.now - start
        try? await Task.sleep(for: .milliseconds(300))
        let bytes = Int(truncatingIfNeeded: InterfaceCounter.receivedBytes() &- before)
        return Outcome(
            title: metadata?.title,
            iconSide: metadata?.iconData.flatMap { pixelSize(of: $0) }.map { Int(max($0.width, $0.height)) },
            imageSize: metadata?.imageData.flatMap { pixelSize(of: $0) },
            failed: metadata == nil,
            milliseconds: elapsed.milliseconds,
            bytes: bytes
        )
    }

    private static func backgroundBytesPerSecond() async throws -> Double {
        let before = InterfaceCounter.receivedBytes()
        try await Task.sleep(for: .seconds(3))
        return Double(InterfaceCounter.receivedBytes() &- before) / 3
    }

    private static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func row(_ number: Int, _ url: URL, _ old: Outcome, _ new: Outcome) -> String {
        let link = (url.host() ?? "") + (url.path().count > 1 ? String(url.path().prefix(24)) : "")
        let same = old.title == new.title ? "=" : "≠"
        let titles = old.title == new.title
            ? quoted(old, length: 70)
            : "\(quoted(old, length: 40)) → \(quoted(new, length: 40))"
        return "| \(number) | \(link) | \(titles) | \(same) | \(icon(old))/\(icon(new)) | \(image(old))/\(image(new)) "
            + "| \(Int(old.milliseconds)) | \(Int(new.milliseconds)) | \(old.bytes / 1024) | \(new.bytes / 1024) |"
    }

    private static func quoted(_ outcome: Outcome, length: Int) -> String {
        if outcome.failed { return "*(nothing)*" }
        guard let title = outcome.title else { return "*(no title)*" }
        let flat = title.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "|", with: "¦")
        return "«" + (flat.count > length ? flat.prefix(length - 1) + "…" : flat) + "»"
    }

    private static func icon(_ outcome: Outcome) -> String {
        outcome.iconSide.map { "\($0)" } ?? "–"
    }

    private static func image(_ outcome: Outcome) -> String {
        outcome.imageSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? "–"
    }

    private static func summarize(_ rows: [(url: URL, old: Outcome, new: Outcome)]) {
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return 0 }
            return sorted.count.isMultiple(of: 2) ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
        }
        let count = rows.count
        print("""

        Links: \(count). Same title: \(rows.filter { $0.old.title == $0.new.title }.count). \
        Icon in both / only LP / only new: \(rows.filter { $0.old.iconSide != nil && $0.new.iconSide != nil }.count) / \
        \(rows.filter { $0.old.iconSide != nil && $0.new.iconSide == nil }.count) / \
        \(rows.filter { $0.old.iconSide == nil && $0.new.iconSide != nil }.count). \
        Image in both / only LP / only new: \(rows.filter { $0.old.imageSize != nil && $0.new.imageSize != nil }.count) / \
        \(rows.filter { $0.old.imageSize != nil && $0.new.imageSize == nil }.count) / \
        \(rows.filter { $0.old.imageSize == nil && $0.new.imageSize != nil }.count).
        Median time: LP \(Int(median(rows.map(\.old.milliseconds)))) ms, new \(Int(median(rows.map(\.new.milliseconds)))) ms. \
        Median bytes: LP \(Int(median(rows.map { Double($0.old.bytes) })) / 1024) KB, new \(Int(median(rows.map { Double($0.new.bytes) })) / 1024) KB. \
        Total: LP \(rows.map(\.old.bytes).reduce(0, +) / 1024) KB, new \(rows.map(\.new.bytes).reduce(0, +) / 1024) KB.
        """)
    }
}

/// Bytes received by the Mac's Ethernet and Wi-Fi interfaces since they came up.
enum InterfaceCounter {
    static func receivedBytes() -> UInt32 {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return 0 }
        defer { freeifaddrs(first) }
        var total: UInt32 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: entry.pointee.ifa_name).hasPrefix("en"),
                  let data = entry.pointee.ifa_data
            else { continue }
            total &+= data.assumingMemoryBound(to: if_data.self).pointee.ifi_ibytes
        }
        return total
    }
}

/// The baseline of the comparison: link metadata from Link Presentation, with the icon and image
/// reduced to the sizes a link card keeps. The address checks of Pasto's providers are left out —
/// every link compared is a public page — and `ImageFitting` is folded in.
enum LegacyLinkMetadataProvider {
    static let iconPixelLimit = 128
    static let imagePointLimit: CGFloat = 512
    static let imageByteLimit = 20 * 1024 * 1024

    @MainActor
    static func metadata(for url: URL) async -> PastoCore.LinkMetadata? {
        guard let metadata = try? await LPMetadataProvider().startFetchingMetadata(for: url) else { return nil }
        let icon = await data(from: metadata.iconProvider)
        let image = await data(from: metadata.imageProvider)
        return PastoCore.LinkMetadata(
            title: metadata.title,
            iconData: icon.flatMap(withinLimit).flatMap(reducedIcon),
            imageData: image.flatMap(withinLimit).flatMap(reducedImage)
        )
    }

    private static func data(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func withinLimit(_ data: Data) -> Data? {
        data.count <= imageByteLimit ? data : nil
    }

    static func reducedIcon(of data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return reducedPNG(of: source, pixelLimit: iconPixelLimit)
    }

    static func reducedImage(of data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0
        else { return nil }
        func points(_ pixels: Int, _ dotsPerInch: Double?) -> CGFloat {
            guard let dotsPerInch, dotsPerInch > 0 else { return CGFloat(pixels) }
            return CGFloat(pixels) * 72 / dotsPerInch
        }
        let pointWidth = points(pixelWidth, properties[kCGImagePropertyDPIWidth] as? Double)
        let pointHeight = points(pixelHeight, properties[kCGImagePropertyDPIHeight] as? Double)
        let scale = min(imagePointLimit / pointWidth, imagePointLimit / pointHeight)
        var side = CGFloat(max(pixelWidth, pixelHeight))
        if scale < 1 {
            side = min(side, (max(pointWidth, pointHeight) * scale * 2).rounded())
        }
        return reducedPNG(of: source, pixelLimit: Int(side))
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
