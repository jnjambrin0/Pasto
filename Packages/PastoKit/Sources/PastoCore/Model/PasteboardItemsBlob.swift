import Foundation

/// The stored form of an item's pasteboard data (`ItemDataEntity.rawPasteboardItems`): the
/// binary property list `PropertyListEncoder` makes of `[PasteboardItemSnapshot]`.
///
/// A copy can be hundreds of megabytes, so neither direction goes the simple way:
/// - **Encoding** produces exactly the bytes `BinaryPropertyList.encode` would, in a buffer
///   allocated once at the final size: the encoder writes the list with stand-ins for the data,
///   and the real bytes go in as it is copied out (`BinaryPropertyListLayout`). The encoder's
///   own output grows as it writes and ends up a quarter larger than the list, on top of the
///   copy being stored.
/// - **Decoding** hands out the data where it lies in the blob, without copying it; the
///   decoder's copies doubled what a paste or a reindex held in memory.
///
/// Both fall back to Foundation's coder for anything they do not expect, so the format is the
/// coder's and nothing stored before or after reads differently.
enum PasteboardItemsBlob {
    static func encode(_ items: [PasteboardItemSnapshot]) throws -> Data {
        if let blob = try? encodeInPlace(items) {
            return blob
        }
        return try BinaryPropertyList.encode(items)
    }

    /// The items, or `nil` when the blob is not one this version can read.
    static func decode(_ blob: Data) -> [PasteboardItemSnapshot]? {
        (try? Reader(blob).items()) ?? (try? BinaryPropertyList.decode([PasteboardItemSnapshot].self, from: blob))
    }

    // MARK: - Encoding

    private static func encodeInPlace(_ items: [PasteboardItemSnapshot]) throws -> Data {
        var standIns = StandIns()
        let skeleton = items.map { item in
            PasteboardItemSnapshot(types: item.types, dataByType: item.dataByType.mapValues { standIns.standIn(for: $0) })
        }
        let layout = try BinaryPropertyListLayout(try BinaryPropertyList.encode(skeleton), offsetWidth: .fewestBytes)
        let substitutes = try layout.dataObjects.map { try standIns.data(standingIn: $0) }
        let size = layout.size(substitutingLengths: { substitutes[$0].count })

        guard let memory = malloc(size) else { throw BinaryPropertyListLayout.FormatError() }
        var sink = BinaryPropertyListLayout.BufferSink(UnsafeMutableRawBufferPointer(start: memory, count: size))
        layout.write(substituting: { substitutes[$0] }, to: &sink)
        guard sink.position == size else {
            free(memory)
            throw BinaryPropertyListLayout.FormatError()
        }
        return Data(bytesNoCopy: memory, count: size, deallocator: .free)
    }

    /// A small, distinct piece of data for every distinct value: the encoder writes equal data
    /// once, so equal values must get equal stand-ins and different ones different stand-ins.
    private struct StandIns {
        private var classes = DataValueClasses()

        mutating func standIn(for data: Data) -> Data {
            withUnsafeBytes(of: UInt64(classes.number(of: data)).littleEndian) { Data($0) }
        }

        func data(standingIn standIn: Data) throws -> Data {
            guard standIn.count == MemoryLayout<UInt64>.size else { throw BinaryPropertyListLayout.FormatError() }
            let index = standIn.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            guard index < UInt64(classes.values.count) else { throw BinaryPropertyListLayout.FormatError() }
            return classes.values[Int(index)]
        }
    }
}

// MARK: - Decoding

extension PasteboardItemsBlob {
    /// Reads exactly the shape the encoder writes — an array of dictionaries with `types`, an
    /// array of strings, and `dataByType`, a dictionary of data by string — and throws at
    /// anything else, which is then left to Foundation's decoder.
    private struct Reader {
        struct Unexpected: Error {}

        /// Data this short is copied out of the blob; longer data is a view into it.
        static let viewThreshold = 64 * 1024

        private let blob: Data
        private let offsets: [Int]
        private let referenceSize: Int
        private let top: Int
        /// Keeps the blob's memory alive for as long as a view into it is.
        private let storage: NSData

        init(_ blob: Data) throws {
            let blob = blob.startIndex == 0 ? blob : Data(blob)
            guard blob.count >= 8 + BinaryPropertyListLayout.trailerSize, blob.prefix(8).elementsEqual("bplist00".utf8) else {
                throw Unexpected()
            }
            let trailerStart = blob.count - BinaryPropertyListLayout.trailerSize
            let offsetSize = Int(blob[trailerStart + 6])
            let referenceSize = Int(blob[trailerStart + 7])
            let count = BinaryPropertyListLayout.integer(in: blob, at: trailerStart + 8, size: 8)
            let top = BinaryPropertyListLayout.integer(in: blob, at: trailerStart + 16, size: 8)
            let tableStart = BinaryPropertyListLayout.integer(in: blob, at: trailerStart + 24, size: 8)
            guard (1...8).contains(offsetSize), (1...8).contains(referenceSize),
                  count > 0, count < UInt64(blob.count), top < count,
                  tableStart <= UInt64(trailerStart), UInt64(trailerStart) - tableStart == count * UInt64(offsetSize)
            else { throw Unexpected() }

            let table = Int(tableStart)
            offsets = try (0..<Int(count)).map { index in
                let offset = Int(BinaryPropertyListLayout.integer(in: blob, at: table + index * offsetSize, size: offsetSize))
                guard offset >= 8, offset < table else { throw Unexpected() }
                return offset
            }
            self.blob = blob
            self.referenceSize = referenceSize
            self.top = Int(top)
            storage = blob as NSData
        }

        func items() throws -> [PasteboardItemSnapshot] {
            try array(at: top).map { reference in
                let entries = try dictionary(at: reference)
                guard let types = entries["types"], let dataByType = entries["dataByType"] else { throw Unexpected() }
                return PasteboardItemSnapshot(
                    types: try array(at: types).map(string(at:)),
                    dataByType: try dictionary(at: dataByType).mapValues(data(at:))
                )
            }
        }

        // MARK: Objects

        private func array(at reference: Int) throws -> [Int] {
            let (marker, count, contentStart) = try header(at: reference)
            guard marker == 0xA else { throw Unexpected() }
            return try references(count: count, at: contentStart)
        }

        /// A dictionary whose keys are strings, by key; references to its values.
        private func dictionary(at reference: Int) throws -> [String: Int] {
            let (marker, count, contentStart) = try header(at: reference)
            guard marker == 0xD else { throw Unexpected() }
            let references = try references(count: count * 2, at: contentStart)
            var entries: [String: Int] = [:]
            entries.reserveCapacity(count)
            for index in 0..<count {
                // Two keys the decoder would read as one: not a case to guess at.
                guard entries.updateValue(references[count + index], forKey: try string(at: references[index])) == nil else {
                    throw Unexpected()
                }
            }
            return entries
        }

        private func string(at reference: Int) throws -> String {
            let (marker, count, contentStart) = try header(at: reference)
            switch marker {
            case 0x5:
                // ASCII, as the encoder writes any string that is.
                guard contentStart + count <= blob.count else { throw Unexpected() }
                let bytes = blob[contentStart..<(contentStart + count)]
                guard bytes.allSatisfy({ $0 < 0x80 }) else { throw Unexpected() }
                return String(decoding: bytes, as: UTF8.self)
            case 0x6:
                // UTF-16, big-endian.
                guard contentStart + count * 2 <= blob.count else { throw Unexpected() }
                let units = (0..<count).map { UInt16(blob[contentStart + 2 * $0]) << 8 | UInt16(blob[contentStart + 2 * $0 + 1]) }
                guard let string = String(validating: units, as: UTF16.self) else { throw Unexpected() }
                return string
            default:
                throw Unexpected()
            }
        }

        private func data(at reference: Int) throws -> Data {
            let (marker, count, contentStart) = try header(at: reference)
            guard marker == 0x4, contentStart + count <= blob.count else { throw Unexpected() }
            guard count >= Self.viewThreshold else {
                return Data(blob[contentStart..<(contentStart + count)])
            }
            // A view of the blob's own memory: no copy, and copied should anyone write to it.
            let storage = storage
            let view = NSData(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: storage.bytes.advanced(by: contentStart)),
                length: count,
                deallocator: { _, _ in withExtendedLifetime(storage) {} }
            )
            return Data(referencing: view)
        }

        // MARK: The format

        /// The kind of the object, its length and where what it holds begins.
        private func header(at reference: Int) throws -> (marker: UInt8, count: Int, contentStart: Int) {
            guard offsets.indices.contains(reference) else { throw Unexpected() }
            let start = offsets[reference]
            let (count, contentStart) = try BinaryPropertyListLayout.length(in: blob, at: start)
            return (blob[start] >> 4, count, contentStart)
        }

        private func references(count: Int, at start: Int) throws -> [Int] {
            guard start + count * referenceSize <= blob.count else { throw Unexpected() }
            return (0..<count).map {
                Int(BinaryPropertyListLayout.integer(in: blob, at: start + $0 * referenceSize, size: referenceSize))
            }
        }
    }
}
