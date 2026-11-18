import CryptoKit
import Foundation
@testable import PastoCore
import Testing

/// The stored blob of pasteboard data and the checksum of unknown content are computed without
/// the copies Foundation's coders make. Existing stores hold blobs and checksums made by those
/// coders: the faster path must give the same bytes and read every blob back the same.
struct BlobEquivalenceTests {
    // MARK: - Inputs

    /// Lengths around every boundary of the format: inline lengths (under 15), one-, two- and
    /// four-byte length integers, and offsets that need two and four bytes.
    private static let lengths = [0, 1, 8, 14, 15, 16, 255, 256, 257, 65_535, 65_536, 70_000]

    private static let types = [
        "public.utf8-plain-text", "public.rtf", "public.png", "public.tiff", "com.adobe.pdf",
        "org.nspasteboard.source", "public.file-url", "x", "é", "dyn.ah62d4rv4ge80e5pe", "漢字.type", "public.url-name",
    ]

    /// Random items made of `types`, with data of `lengths` and, often, the same bytes or the
    /// same `Data` under several types and items.
    private static func randomItems(seed: UInt64) -> [PasteboardItemSnapshot] {
        var random = SeededRandom(seed: seed)
        var pool: [Data] = []
        func data() -> Data {
            if !pool.isEmpty, Int.random(in: 0..<4, using: &random) == 0 {
                return pool.randomElement(using: &random)!
            }
            let length = lengths.randomElement(using: &random)!
            let value = Data((0..<length).map { _ in UInt8.random(in: 0...3, using: &random) })
            pool.append(value)
            return value
        }
        return (0..<Int.random(in: 0...6, using: &random)).map { _ in
            let types = Array(Self.types.shuffled(using: &random).prefix(Int.random(in: 0...6, using: &random)))
            var dataByType: [String: Data] = [:]
            for type in types where Int.random(in: 0..<8, using: &random) != 0 {
                // A type now and then has no data, and data now and then has no type.
                dataByType[type] = data()
            }
            if Int.random(in: 0..<6, using: &random) == 0 {
                dataByType["com.example.undeclared"] = data()
            }
            return PasteboardItemSnapshot(types: types, dataByType: dataByType)
        }
    }

    private static let seeds = Array(UInt64(1)...60)

    /// Hundreds of objects, so that references take two bytes.
    private static let manyItems = (0..<300).map { index in
        PasteboardItemSnapshot(types: ["type.\(index)"], dataByType: ["type.\(index)": Data("value \(index)".utf8)])
    }

    // MARK: - The blob

    @Test(arguments: seeds)
    func theBlobIsWhatFoundationWritesByteForByte(seed: UInt64) throws {
        let items = Self.randomItems(seed: seed)
        #expect(try PasteboardItemsBlob.encode(items) == BinaryPropertyList.encode(items))
    }

    @Test func manyObjectsAndEveryLengthAreWrittenTheSame() throws {
        #expect(try PasteboardItemsBlob.encode(Self.manyItems) == BinaryPropertyList.encode(Self.manyItems))
        for length in Self.lengths + [1_048_576] {
            let items = [PasteboardItemSnapshot(types: ["a", "b"], dataByType: ["a": Data(count: length), "b": Data(repeating: 7, count: length)])]
            #expect(try PasteboardItemsBlob.encode(items) == BinaryPropertyList.encode(items), "length \(length)")
        }
    }

    @Test(arguments: seeds)
    func theBlobReadsBackAsFoundationReadsIt(seed: UInt64) throws {
        let items = Self.randomItems(seed: seed)
        let blob = try BinaryPropertyList.encode(items)
        let expected = try BinaryPropertyList.decode([PasteboardItemSnapshot].self, from: blob)
        #expect(PasteboardItemsBlob.decode(blob) == expected)
        #expect(PasteboardItemsBlob.decode(blob) == items)
    }

    @Test func largeDataIsReadWhereItLiesInTheBlob() throws {
        let payload = Data(repeating: 0x5A, count: 1_000_000)
        let blob = try PasteboardItemsBlob.encode([PasteboardItemSnapshot(types: ["public.tiff"], dataByType: ["public.tiff": payload])])
        let decoded = try #require(PasteboardItemsBlob.decode(blob)?.first?.dataByType["public.tiff"])

        let blobRange = blob.withUnsafeBytes { UInt(bitPattern: $0.baseAddress!)..<UInt(bitPattern: $0.baseAddress! + $0.count) }
        #expect(decoded.withUnsafeBytes { blobRange.contains(UInt(bitPattern: $0.baseAddress!)) })
        #expect(decoded == payload)
        #expect(decoded.startIndex == 0)

        // Writing to it copies it first: the blob is never changed.
        var changed = decoded
        changed[0] = 0
        #expect(PasteboardItemsBlob.decode(blob)?.first?.dataByType["public.tiff"] == payload)
    }

    /// Blobs written by Foundation's encoder before this version, as they are in the user's store.
    private static let pinnedBlobs: [(items: [PasteboardItemSnapshot], hex: String)] = [
        (
            [PasteboardItemSnapshot(types: ["public.utf8-plain-text"], dataByType: ["public.utf8-plain-text": Data("hola".utf8)])],
            "62706c6973743030a101d2020304065574797065735a64617461427954797065a1055f10167075626c69632e757466382d706c61696e2d7465"
                + "7874d1050744686f6c61080a0f1520223b3e0000000000000101000000000000000800000000000000000000000000000043"
        ),
        (
            [PasteboardItemSnapshot(
                types: ["public.png", "public.tiff", "org.nspasteboard.source"],
                dataByType: [
                    "public.png": Data((0..<40).map { UInt8($0) }),
                    "public.tiff": Data((0..<300).map { UInt8($0 % 7) }),
                    "org.nspasteboard.source": Data(),
                ]
            )],
            "62706c6973743030a101d2020304085574797065735a64617461427954797065a30506075a7075626c69632e706e675b7075626c69632e7469"
                + "66665f10176f72672e6e737061737465626f6172642e736f75726365d3070506090a0b404f1028000102030405060708090a0b0c0d0e0f10"
                + "1112131415161718191a1b1c1d1e1f20212223242526274f11012c" + String(repeating: "00010203040506", count: 42) + "000102030405"
                + "0008000a000f001500200024002f003b0055005c005d00880000000000000201000000000000000c000000000000000000000000000001b8"
        ),
        (
            [
                PasteboardItemSnapshot(types: ["é", "public.rtf"], dataByType: ["é": Data("ñ".utf8), "public.rtf": Data("ñ".utf8)]),
                PasteboardItemSnapshot(
                    types: ["missing", "public.rtf"],
                    dataByType: ["public.rtf": Data(repeating: 9, count: 20), "extra": Data([1])]
                ),
            ],
            "62706c6973743030a20109d2020304075574797065735a64617461427954797065a205066100e95a7075626c69632e727466d20605080842c3"
                + "b1d202030a0ca20b06576d697373696e67d20d060e0f55657874726141014f101409090909090909090909090909090909090909090"
                + "80b101621242732373a3f424a4f5557000000000000010100000000000000100000000000000000000000000000006e"
        ),
    ]

    @Test func blobsWrittenBeforeReadTheSameAndAreWrittenTheSame() throws {
        for (items, hex) in Self.pinnedBlobs {
            let blob = try #require(Data(hexadecimal: hex))
            #expect(PasteboardItemsBlob.decode(blob) == items)
            #expect(try PasteboardItemsBlob.encode(items) == blob)
        }
    }

    @Test func aBlobOfAnotherShapeIsLeftToFoundation() throws {
        let items = Self.randomItems(seed: 7)
        // An XML property list decodes the same, through Foundation's decoder.
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        #expect(PasteboardItemsBlob.decode(try encoder.encode(items)) == items)
        // What neither can read is no items.
        #expect(PasteboardItemsBlob.decode(Data("bplist00 truncated".utf8)) == nil)
        #expect(PasteboardItemsBlob.decode(Data()) == nil)
    }

    // MARK: - The checksum of unknown content

    /// The archive as it was built before, hashed whole.
    private func archiveDigest(of items: [PasteboardItemSnapshot]) -> String? {
        guard !items.isEmpty else { return nil }
        let representation = items.map { item in
            item.types.map { [$0 as NSString, (item.dataByType[$0] ?? Data()) as NSData] as NSArray } as NSArray
        } as NSArray
        guard let archive = try? NSKeyedArchiver.archivedData(withRootObject: representation, requiringSecureCoding: true) else {
            return nil
        }
        return Insecure.MD5.hash(data: archive).map { String(format: "%02x", $0) }.joined()
    }

    @Test(arguments: seeds)
    func unknownContentHashesAsItsArchiveDid(seed: UInt64) {
        let items = Self.randomItems(seed: seed)
        #expect(ItemChecksum.checksum(of: items, type: .unknown) == archiveDigest(of: items))
    }

    @Test func unknownContentOfEveryLengthHashesAsItsArchiveDid() {
        #expect(ItemChecksum.checksum(of: Self.manyItems, type: .unknown) == archiveDigest(of: Self.manyItems))
        for length in Self.lengths + [1_048_576] {
            let shared = Data(repeating: 3, count: length)
            let items = [
                PasteboardItemSnapshot(types: ["a", "b", "c"], dataByType: ["a": shared, "b": shared, "c": Data(count: length)]),
                PasteboardItemSnapshot(types: ["a", "missing"], dataByType: ["a": Data(repeating: 3, count: length)]),
            ]
            #expect(ItemChecksum.checksum(of: items, type: .unknown) == archiveDigest(of: items), "length \(length)")
        }
    }
}

private extension Data {
    init?(hexadecimal: String) {
        var bytes: [UInt8] = []
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2, limitedBy: hexadecimal.endIndex) ?? hexadecimal.endIndex
            guard let byte = UInt8(hexadecimal[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
