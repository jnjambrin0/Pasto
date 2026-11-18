import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What is copied in a capture run, as files on disk: the fake pasteboard reads each
/// representation into fresh memory when it is asked for it, the way data arrives from the
/// pasteboard server.
enum PayloadKind: String, CaseIterable {
    /// Plain text as UTF-8: words, accents and line breaks, like a large log or document.
    case text
    /// An image as an uncompressed TIFF and a PNG of the same pixels, half the size each.
    case image
    /// Bytes of a type capture does not know (`com.adobe.pdf`): hashed and stored whole.
    case data
    /// An image as an uncompressed TIFF only, as some applications copy it: pasting it writes
    /// a PNG copy of it.
    case tiff
}

struct Payload {
    struct Representation {
        let type: String
        let file: URL
    }

    let kind: PayloadKind
    let megabytes: Int
    let representations: [Representation]

    var byteCount: Int {
        representations.reduce(0) { total, representation in
            total + ((try? representation.file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// The payload's files in `directory`, made now unless they are already there.
    static func prepared(_ kind: PayloadKind, megabytes: Int, in directory: URL) throws -> Payload {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = megabytes * 1_048_576
        let base = directory.appending(path: "\(kind.rawValue)-\(megabytes)")
        switch kind {
        case .text:
            let file = base.appendingPathExtension("txt")
            if !FileManager.default.fileExists(atPath: file.path) {
                try writeText(byteCount: bytes, to: file)
            }
            return Payload(kind: kind, megabytes: megabytes, representations: [.init(type: "public.utf8-plain-text", file: file)])
        case .data:
            let file = base.appendingPathExtension("bin")
            if !FileManager.default.fileExists(atPath: file.path) {
                try writeRandomBytes(byteCount: bytes, to: file)
            }
            return Payload(kind: kind, megabytes: megabytes, representations: [.init(type: "com.adobe.pdf", file: file)])
        case .tiff:
            // The TIFF of the image payload of twice the size: same pixels, this size alone.
            let image = try prepared(.image, megabytes: megabytes * 2, in: directory)
            return Payload(kind: kind, megabytes: megabytes, representations: image.representations.filter { $0.type == "public.tiff" })
        case .image:
            let tiff = base.appendingPathExtension("tiff")
            let png = base.appendingPathExtension("png")
            if !FileManager.default.fileExists(atPath: tiff.path) || !FileManager.default.fileExists(atPath: png.path) {
                // Noise does not compress: TIFF and PNG each take about 3 bytes a pixel (RGB).
                let side = Int((Double(bytes) / 6).squareRoot())
                try writeNoiseImage(side: side, tiff: tiff, png: png)
            }
            // The order an application such as Preview declares them in.
            return Payload(kind: kind, megabytes: megabytes, representations: [
                .init(type: "public.tiff", file: tiff),
                .init(type: "public.png", file: png),
            ])
        }
    }

    // MARK: - Making the files

    private static let words = [
        "pasteboard", "history", "capture", "árbol", "canción", "pingüino", "the", "of", "and", "Mañana",
        "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do",
        "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "2026-11-20",
        "{", "}", "func", "let", "return", "if", "else", "0x1f3a", "error:", "warning:",
    ]

    private static func writeText(byteCount: Int, to file: URL) throws {
        var generator = SystemRandomNumberGenerator()
        // A few megabytes of varied text, repeated with a counter so that no block repeats exactly.
        var block = ""
        while block.utf8.count < 4_194_304 {
            let line = (0..<12).map { _ in words.randomElement(using: &generator)! }.joined(separator: " ")
            block += line + "\n"
        }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var written = 0
        var counter = 0
        while written < byteCount {
            counter += 1
            let chunk = Data("— bloque \(counter) —\n".utf8) + Data(block.utf8)
            let part = chunk.prefix(byteCount - written)
            try handle.write(contentsOf: part)
            written += part.count
        }
    }

    private static func writeRandomBytes(byteCount: Int, to file: URL) throws {
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var generator = SystemRandomNumberGenerator()
        let chunkSize = 8 * 1_048_576
        var written = 0
        while written < byteCount {
            let count = min(chunkSize, byteCount - written)
            var chunk = Data(count: count)
            chunk.withUnsafeMutableBytes { buffer in
                let words = buffer.bindMemory(to: UInt64.self)
                for index in words.indices { words[index] = generator.next() }
            }
            try handle.write(contentsOf: chunk)
            written += count
        }
    }

    private static func writeNoiseImage(side: Int, tiff: URL, png: URL) throws {
        let bytesPerRow = side * 4
        var pixels = Data(count: bytesPerRow * side)
        var generator = SystemRandomNumberGenerator()
        pixels.withUnsafeMutableBytes { buffer in
            let words = buffer.bindMemory(to: UInt64.self)
            // Opaque noise: every fourth byte (alpha) is 255.
            for index in words.indices { words[index] = generator.next() | 0xFF00_0000_FF00_0000 }
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { throw BenchError("could not make the image") }
        try write(image, as: .tiff, to: tiff, properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1],
        ])
        try write(image, as: .png, to: png, properties: [:])
    }

    private static func write(_ image: CGImage, as type: UTType, to file: URL, properties: [CFString: Any]) throws {
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, 1, nil) else {
            throw BenchError("could not create \(file.lastPathComponent)")
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BenchError("could not write \(file.lastPathComponent)") }
    }
}

struct BenchError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
