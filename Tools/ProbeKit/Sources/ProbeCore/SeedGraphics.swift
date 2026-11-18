import CoreGraphics
import CoreText
import Foundation

/// Images drawn at run time so that the seed set needs no bundled resources.
public enum SeedImage: Sendable {
    case gradient
    case transparentBadge

    public func pngData() throws -> Data {
        switch self {
        case .gradient:
            try Self.render(width: 640, height: 400) { context in
                Self.drawGradient(in: context, width: 640, height: 400)
                Self.drawLabel("ProbeKit seed · 640 × 400", in: context, at: CGPoint(x: 32, y: 40), size: 36)
            }
        case .transparentBadge:
            try Self.render(width: 96, height: 96) { context in
                context.setFillColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 0.85)
                context.fillEllipse(in: CGRect(x: 8, y: 8, width: 80, height: 80))
                context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
                context.setLineWidth(6)
                context.strokeEllipse(in: CGRect(x: 26, y: 26, width: 44, height: 44))
            }
        }
    }

    private static func render(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw ProbeError.runtime("cannot create a \(width)x\(height) drawing context") }
        draw(context)
        guard let image = context.makeImage() else { throw ProbeError.runtime("cannot render the seed image") }
        return try PNGFile.data(image)
    }

    private static func drawGradient(in context: CGContext, width: CGFloat, height: CGFloat) {
        let colors = [
            CGColor(srgbRed: 0.369, green: 0.361, blue: 0.902, alpha: 1),
            CGColor(srgbRed: 1, green: 0.216, blue: 0.373, alpha: 1),
            CGColor(srgbRed: 1, green: 0.584, blue: 0, alpha: 1),
        ]
        guard let gradient = CGGradient(colorsSpace: context.colorSpace, colors: colors as CFArray, locations: [0, 0.6, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    }

    static func drawLabel(_ text: String, in context: CGContext, at origin: CGPoint, size: CGFloat, gray: CGFloat = 1) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = origin
        CTLineDraw(line, context)
    }
}

/// Files created on demand under the fixtures folder, for seeding file copies.
public enum FixtureFile: String, CaseIterable, Sendable {
    case text = "probekit-note.txt"
    case pdf = "probekit-document.pdf"
    case png = "probekit-picture.png"

    /// `Tools/ProbeKit/.fixtures`, located from this source file because the tool runs in place.
    public static let defaultDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".fixtures", isDirectory: true)

    /// Returns the file's URL inside `directory`, writing the file first if it is not there yet.
    public func materialize(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(rawValue)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            switch self {
            case .text:
                try Data("ProbeKit fixture: a small text file used to seed file copies.\n".utf8).write(to: url)
            case .png:
                try SeedImage.gradient.pngData().write(to: url)
            case .pdf:
                try Self.writePDF(to: url)
            }
        } catch let error as ProbeError {
            throw error
        } catch {
            throw ProbeError.runtime("cannot create fixture \(url.path): \(error.localizedDescription)")
        }
        return url
    }

    private static func writePDF(to url: URL) throws {
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else {
            throw ProbeError.runtime("cannot create fixture \(url.path)")
        }
        context.beginPDFPage(nil)
        SeedImage.drawLabel("ProbeKit fixture document", in: context, at: CGPoint(x: 72, y: 700), size: 24, gray: 0)
        context.endPDFPage()
        context.closePDF()
    }
}
