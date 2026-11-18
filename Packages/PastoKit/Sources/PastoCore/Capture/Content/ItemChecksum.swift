import CryptoKit
import Foundation

/// The deduplication key of an item: an MD5 of what the item *is*, as 32 lowercase hexadecimal
/// digits.
///
/// What is hashed depends on the type, and deliberately leaves things out: formatting does not
/// count for text, nor the trailing slash for a web address. Nothing else is normalised — one
/// more space is another item.
enum ItemChecksum {
    private static let filesPrefix = "FileSnippet:"

    /// `nil` when there is nothing to hash; the content is then not stored.
    static func checksum(of items: [PasteboardItemSnapshot], type: ItemType) -> String? {
        checksum(of: CaptureReading(items), type: type)
    }

    /// The hash is fed the bytes where they already are — the string's own UTF-8, each image's
    /// data — so that a large copy is never copied again to be hashed.
    static func checksum(of reading: CaptureReading, type: ItemType) -> String? {
        let items = reading.items
        switch type {
        case .text, .color:
            return reading.text.map(digest(utf8:))
        case .link:
            return reading.text.map { digest(utf8: LinkNormalizer.normalized($0)) }
        case .image:
            // Every item's image feeds one hash, in order.
            let images = items.compactMap(\.imageData)
            return images.isEmpty ? nil : digest(images)
        case .files:
            // Every path, one after another, with nothing in between.
            let paths = items.compactMap(\.filePath)
            return paths.isEmpty ? nil : digest(utf8: filesPrefix + paths.joined())
        case .unknown:
            // Content of no known kind is hashed whole, as a keyed archive of each item's types
            // in order, each with its data. The archive is built from arrays only, so that it
            // comes out the same on every run, and it is hashed as it is archived, without ever
            // being built (`ContentArchiveDigest`).
            return autoreleasepool { ContentArchiveDigest.digest(of: items).map(hexadecimal) }
        }
    }

    private static func digest(_ chunks: [Data]) -> String {
        var hash = Insecure.MD5()
        chunks.forEach { hash.update(data: $0) }
        return hexadecimal(hash.finalize())
    }

    /// The MD5 of `string`'s UTF-8 bytes, read in place: the same as hashing `Data(string.utf8)`.
    private static func digest(utf8 string: String) -> String {
        var hash = Insecure.MD5()
        var string = string
        string.withUTF8 { hash.update(bufferPointer: UnsafeRawBufferPointer($0)) }
        return hexadecimal(hash.finalize())
    }

    private static func hexadecimal(_ digest: Insecure.MD5Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
