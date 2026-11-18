import Foundation

/// The object table of a binary property list ("bplist00"), read so that it can be written out
/// again with other bytes in its data objects.
///
/// This is how a property list holding hundreds of megabytes is produced without building it in
/// memory first: the encoder writes the list with a small stand-in for every data object, and
/// the stand-ins are swapped for the real bytes as the list is written out — into a buffer of
/// exactly the final size, or straight into a hash. Every other byte is the encoder's own, so
/// the result is what the encoder would have written for the real data, byte for byte, as long
/// as it treats the stand-ins as it treats the data: equal stand-ins where the data is equal.
///
/// The parts that change with the size of a data object follow the format: the object's length
/// (an integer object of 1, 2, 4 or 8 bytes from 15 bytes on), the offsets of the objects after
/// it, and the width of the offset table — the fewest bytes that hold the table's own offset,
/// which Core Foundation rounds up to 1, 2, 4 or 8 and Foundation's Swift encoder does not.
struct BinaryPropertyListLayout {
    struct FormatError: Error {}

    /// How the writer sizes the entries of the offset table.
    enum OffsetWidth {
        /// The fewest bytes, from 1 to 8: `PropertyListEncoder`.
        case fewestBytes
        /// The fewest of 1, 2, 4 or 8 bytes: Core Foundation, and so `NSKeyedArchiver`.
        case powerOfTwo

        func width(of value: UInt64) -> Int {
            let bytes = max(1, (64 - value.leadingZeroBitCount + 7) / 8)
            switch self {
            case .fewestBytes: return bytes
            case .powerOfTwo: return bytes <= 2 ? bytes : bytes <= 4 ? 4 : 8
            }
        }
    }

    /// Where the list is written to.
    protocol Sink {
        mutating func write(_ bytes: UnsafeRawBufferPointer)
    }

    private struct Object {
        var range: Range<Int>
        var isData: Bool
    }

    private let list: Data
    private let objects: [Object]
    /// The bytes before the first object: the magic number and version.
    private let headerEnd: Int
    /// The trailer's first six bytes (unused, and the sort version), kept as they are.
    private let trailerPrefix: Range<Int>
    private let objectReferenceSize: UInt8
    private let topObject: UInt64
    private let offsetWidth: OffsetWidth

    static let trailerSize = 32

    /// - Parameter offsetWidth: The rule of the writer that wrote `list`, which the list is
    ///   written out again with.
    /// - Throws: `FormatError` for anything but a binary property list whose objects lie one
    ///   after another in the order of the offset table, which is how every writer lays them out.
    init(_ list: Data, offsetWidth: OffsetWidth) throws {
        // Indices from zero, whatever the data is a slice of.
        let list = list.startIndex == 0 ? list : Data(list)
        guard list.count >= 8 + Self.trailerSize, list.prefix(8).elementsEqual("bplist00".utf8) else { throw FormatError() }

        let trailerStart = list.count - Self.trailerSize
        let offsetSize = Int(list[trailerStart + 6])
        let referenceSize = list[trailerStart + 7]
        let count = Self.integer(in: list, at: trailerStart + 8, size: 8)
        let top = Self.integer(in: list, at: trailerStart + 16, size: 8)
        let tableStart = Self.integer(in: list, at: trailerStart + 24, size: 8)
        guard (1...8).contains(offsetSize), (1...8).contains(Int(referenceSize)),
              count > 0, count < UInt64(list.count), top < count,
              tableStart <= UInt64(trailerStart), UInt64(trailerStart) - tableStart == count * UInt64(offsetSize)
        else { throw FormatError() }

        let table = Int(tableStart)
        let offsets = (0..<Int(count)).map { Int(Self.integer(in: list, at: table + $0 * offsetSize, size: offsetSize)) }
        guard offsets[0] >= 8 else { throw FormatError() }
        var objects: [Object] = []
        objects.reserveCapacity(offsets.count)
        for (index, start) in offsets.enumerated() {
            let end = index + 1 < offsets.count ? offsets[index + 1] : table
            guard start < end else { throw FormatError() }
            let isData = list[start] >> 4 == 0x4
            if isData {
                // A data object takes exactly the space up to the next one.
                let (length, contentStart) = try Self.length(in: list, at: start)
                guard contentStart + length == end else { throw FormatError() }
            }
            objects.append(Object(range: start..<end, isData: isData))
        }

        self.list = list
        self.objects = objects
        headerEnd = offsets[0]
        trailerPrefix = trailerStart..<(trailerStart + 6)
        objectReferenceSize = referenceSize
        topObject = top
        self.offsetWidth = offsetWidth
    }

    /// The bytes of each data object of the list, in the order they appear.
    var dataObjects: [Data] {
        objects.lazy.filter(\.isData).map { object in
            // Validated by the initializer.
            let contentStart = (try? Self.length(in: list, at: object.range.lowerBound).contentStart) ?? object.range.upperBound
            return list[contentStart..<object.range.upperBound]
        }
    }

    /// How many bytes `write(substituting:to:)` writes.
    ///
    /// - Parameter length: How long the bytes that take the place of each data object are, in
    ///   the order of `dataObjects`.
    func size(substitutingLengths length: (Int) -> Int) -> Int {
        var end = headerEnd
        var dataIndex = 0
        for object in objects {
            if object.isData {
                end += Self.dataHeader(length: length(dataIndex)).count + length(dataIndex)
                dataIndex += 1
            } else {
                end += object.range.count
            }
        }
        return end + objects.count * offsetWidth.width(of: UInt64(end)) + Self.trailerSize
    }

    /// Writes the list with `substitute(i)` in place of the bytes of the `i`th data object.
    func write<S: Sink>(substituting substitute: (Int) -> Data, to sink: inout S) {
        list.withUnsafeBytes { list in
            sink.write(UnsafeRawBufferPointer(rebasing: list[0..<headerEnd]))
            var offsets: [UInt64] = []
            offsets.reserveCapacity(objects.count)
            var position = headerEnd
            var dataIndex = 0
            for object in objects {
                offsets.append(UInt64(position))
                guard object.isData else {
                    sink.write(UnsafeRawBufferPointer(rebasing: list[object.range]))
                    position += object.range.count
                    continue
                }
                let replacement = substitute(dataIndex)
                dataIndex += 1
                let header = Self.dataHeader(length: replacement.count)
                header.withUnsafeBytes { sink.write($0) }
                replacement.withUnsafeBytes { sink.write($0) }
                position += header.count + replacement.count
            }

            let tableStart = UInt64(position)
            let width = offsetWidth.width(of: tableStart)
            var table: [UInt8] = []
            table.reserveCapacity(offsets.count * width + Self.trailerSize)
            for offset in offsets {
                Self.append(offset, width: width, to: &table)
            }
            table.append(contentsOf: list[trailerPrefix])
            table.append(UInt8(width))
            table.append(objectReferenceSize)
            Self.append(UInt64(objects.count), width: 8, to: &table)
            Self.append(topObject, width: 8, to: &table)
            Self.append(tableStart, width: 8, to: &table)
            table.withUnsafeBytes { sink.write($0) }
        }
    }

    // MARK: - The format

    /// The marker of a data object of `length` bytes, followed from 15 bytes on by the length
    /// as an integer object.
    private static func dataHeader(length: Int) -> [UInt8] {
        guard length >= 15 else { return [0x40 | UInt8(length)] }
        // An integer object is always 1, 2, 4 or 8 bytes: its marker holds the power of two.
        let width = OffsetWidth.powerOfTwo.width(of: UInt64(length))
        var header: [UInt8] = [0x4F, 0x10 | UInt8(width.trailingZeroBitCount)]
        append(UInt64(length), width: width, to: &header)
        return header
    }

    /// The length of the object at `start` — bytes of data, characters of a string, elements of
    /// an array, entries of a dictionary — and where what it holds begins.
    static func length(in list: Data, at start: Int) throws -> (length: Int, contentStart: Int) {
        let marker = list[start] & 0x0F
        guard marker == 0x0F else { return (Int(marker), start + 1) }
        guard start + 1 < list.count, list[start + 1] >> 4 == 0x1 else { throw FormatError() }
        let size = 1 << Int(list[start + 1] & 0x0F)
        guard size <= 8, start + 2 + size <= list.count else { throw FormatError() }
        let length = integer(in: list, at: start + 2, size: size)
        guard length <= UInt64(list.count) else { throw FormatError() }
        return (Int(length), start + 2 + size)
    }

    /// The big-endian unsigned integer of `size` bytes at `start`.
    static func integer(in data: Data, at start: Int, size: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in start..<(start + size) {
            value = value << 8 | UInt64(data[index])
        }
        return value
    }

    private static func append(_ value: UInt64, width: Int, to bytes: inout [UInt8]) {
        for shift in stride(from: (width - 1) * 8, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
}

extension BinaryPropertyListLayout {
    /// Writes into memory of exactly the size of the list.
    struct BufferSink: Sink {
        private let buffer: UnsafeMutableRawBufferPointer
        private(set) var position = 0

        init(_ buffer: UnsafeMutableRawBufferPointer) {
            self.buffer = buffer
        }

        mutating func write(_ bytes: UnsafeRawBufferPointer) {
            guard !bytes.isEmpty else { return }
            precondition(position + bytes.count <= buffer.count, "The list is longer than its size")
            buffer.baseAddress!.advanced(by: position).copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
            position += bytes.count
        }
    }
}
