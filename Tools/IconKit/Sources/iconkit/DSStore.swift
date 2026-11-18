import Foundation

/// Reads and writes Finder's `.DS_Store` files: the window layout of a folder (here, the DMG's
/// volume) without asking Finder to do it.
///
/// The format is not documented by Apple; this follows the public descriptions of it (Mark
/// Mentovai's and Wim Lewis's descriptions of the "Bud1" buddy-allocated file and its B-tree) and was
/// checked against `.DS_Store` files that Finder and other DMG tools wrote. Everything is big-endian.
///
/// - The file starts with `00 00 00 01`, then a buddy allocator: magic `Bud1`, the offset and size of
///   its bookkeeping block (twice the offset) and 16 unused bytes. Offsets count from byte 4.
/// - The bookkeeping block lists every block's address (offset | log2(size)), a table of contents
///   (`DSDB` → the B-tree's master block) and 32 free lists, one per block size.
/// - The master block gives the B-tree's root node, its depth, the record and node counts and the
///   page size. A node is `P` (0 for a leaf, else the rightmost child), a count, and the records (in
///   an internal node, each preceded by the child that holds the smaller records).
/// - A record is the file name (UTF-16 length and characters), a four-character property code, a
///   four-character type and the value. Records are sorted by name, case-insensitively, then code.
enum DSStore {
    enum Value: Equatable, CustomStringConvertible {
        case long(UInt32)
        case short(UInt16)
        case bool(Bool)
        case type(String)
        case blob(Data)
        case ustr(String)
        case comp(UInt64)
        case dutc(UInt64)

        var description: String {
            switch self {
            case let .long(value): "long \(value)"
            case let .short(value): "shor \(value)"
            case let .bool(value): "bool \(value)"
            case let .type(value): "type '\(value)'"
            case let .blob(data): "blob \(data.count) bytes"
            case let .ustr(value): "ustr \"\(value)\""
            case let .comp(value): "comp \(value)"
            case let .dutc(value): "dutc \(value)"
            }
        }
    }

    struct Record: Equatable {
        var name: String
        var code: String
        var value: Value

        /// Finder's order: by name, case-insensitively, then by property code.
        static func precedes(_ a: Record, _ b: Record) -> Bool {
            let left = Array(a.name.lowercased().utf16), right = Array(b.name.lowercased().utf16)
            if left != right { return left.lexicographicallyPrecedes(right) }
            return Array(a.code.utf8).lexicographicallyPrecedes(Array(b.code.utf8))
        }
    }

    // MARK: Writing

    /// Fixed layout for a small store: the header (32 bytes at 0), the master block (32 at 64), one
    /// leaf node (4096 at 4096) and the bookkeeping block (2048 at 8192). Every other range of the
    /// 2³¹-byte address space is described as free, as Finder's own allocator would.
    private static let masterAddress = (offset: 64, log2Size: 5)
    private static let leafAddress = (offset: 4096, log2Size: 12)
    private static let rootAddress = (offset: 8192, log2Size: 11)
    private static let pageSize: UInt32 = 0x1000

    static func encode(_ records: [Record]) throws -> Data {
        let sorted = records.sorted(by: Record.precedes)

        var leaf = Data()
        leaf.appendUInt32(0)
        leaf.appendUInt32(UInt32(sorted.count))
        for record in sorted {
            try leaf.append(encode(record))
        }
        guard leaf.count <= 1 << leafAddress.log2Size else {
            throw IconKitError("the .DS_Store records do not fit one node (\(leaf.count) bytes)")
        }

        var master = Data()
        // Block numbers: 0 is the bookkeeping block, 1 the master, 2 the leaf.
        master.appendUInt32(2)
        master.appendUInt32(0)
        master.appendUInt32(UInt32(sorted.count))
        master.appendUInt32(1)
        master.appendUInt32(pageSize)

        let addresses = [rootAddress, masterAddress, leafAddress].map { UInt32($0.offset) | UInt32($0.log2Size) }
        var root = Data()
        root.appendUInt32(UInt32(addresses.count))
        root.appendUInt32(0)
        for index in 0..<256 {
            root.appendUInt32(index < addresses.count ? addresses[index] : 0)
        }
        root.appendUInt32(1)
        root.append(UInt8(4))
        root.append(contentsOf: Array("DSDB".utf8))
        root.appendUInt32(1)
        let allocated = [(0, 5), masterAddress, leafAddress, rootAddress].map { (offset: $0.0, log2Size: $0.1) }
        let free = freeLists(allocated: allocated)
        for list in free {
            root.appendUInt32(UInt32(list.count))
            for offset in list { root.appendUInt32(UInt32(offset)) }
        }
        guard root.count <= 1 << rootAddress.log2Size else { throw IconKitError("the .DS_Store bookkeeping block overflows") }

        // The address space starts at file byte 4; the file ends with the last block.
        let end = rootAddress.offset + (1 << rootAddress.log2Size)
        var file = Data(count: 4 + end)
        file.replace(at: 0, with: Data([0, 0, 0, 1]))
        var header = Data()
        header.append(contentsOf: Array("Bud1".utf8))
        header.appendUInt32(UInt32(rootAddress.offset))
        header.appendUInt32(UInt32(1 << rootAddress.log2Size))
        header.appendUInt32(UInt32(rootAddress.offset))
        header.append(Data(count: 16))
        file.replace(at: 4, with: header)
        file.replace(at: 4 + masterAddress.offset, with: master)
        file.replace(at: 4 + leafAddress.offset, with: leaf)
        file.replace(at: 4 + rootAddress.offset, with: root)
        return file
    }

    /// The buddy allocator's free lists for these allocated blocks: every maximal aligned block that
    /// holds none of them, filed under its size (index = log2 of the size).
    static func freeLists(allocated: [(offset: Int, log2Size: Int)]) -> [[Int]] {
        var lists = Array(repeating: [Int](), count: 32)
        func visit(_ offset: Int, _ log2Size: Int) {
            let size = 1 << log2Size
            let inside = allocated.filter { $0.offset >= offset && $0.offset < offset + size }
            if inside.isEmpty {
                lists[log2Size].append(offset)
            } else if !(inside.count == 1 && inside[0].offset == offset && inside[0].log2Size == log2Size) {
                visit(offset, log2Size - 1)
                visit(offset + size / 2, log2Size - 1)
            }
        }
        visit(0, 31)
        return lists.map { $0.sorted() }
    }

    private static func encode(_ record: Record) throws -> Data {
        var data = Data()
        let name = Array(record.name.utf16)
        data.appendUInt32(UInt32(name.count))
        for unit in name { data.appendUInt16(unit) }
        data.append(try fourCC(record.code))
        switch record.value {
        case let .long(value):
            data.append(try fourCC("long")); data.appendUInt32(value)
        case let .short(value):
            data.append(try fourCC("shor")); data.appendUInt32(UInt32(value))
        case let .bool(value):
            data.append(try fourCC("bool")); data.append(value ? 1 : 0)
        case let .type(value):
            data.append(try fourCC("type")); data.append(try fourCC(value))
        case let .blob(blob):
            data.append(try fourCC("blob")); data.appendUInt32(UInt32(blob.count)); data.append(blob)
        case let .ustr(value):
            let units = Array(value.utf16)
            data.append(try fourCC("ustr")); data.appendUInt32(UInt32(units.count))
            for unit in units { data.appendUInt16(unit) }
        case let .comp(value):
            data.append(try fourCC("comp")); data.appendUInt64(value)
        case let .dutc(value):
            data.append(try fourCC("dutc")); data.appendUInt64(value)
        }
        return data
    }

    private static func fourCC(_ code: String) throws -> Data {
        let bytes = Array(code.utf8)
        guard bytes.count == 4 else { throw IconKitError("'\(code)' is not a four-character code") }
        return Data(bytes)
    }

    // MARK: Reading

    /// Every record in the store, in file order. Reads any store, including Finder's own multi-node
    /// ones.
    static func decode(_ file: Data) throws -> [Record] {
        let bytes = [UInt8](file)
        let reader = Reader(bytes: bytes)
        guard bytes.count > 36, reader.uint32(at: 0) == 1, String(decoding: bytes[4..<8], as: UTF8.self) == "Bud1" else {
            throw IconKitError("not a .DS_Store file")
        }
        let rootOffset = Int(reader.uint32(at: 8)), rootSize = Int(reader.uint32(at: 12))
        guard reader.uint32(at: 16) == UInt32(rootOffset), 4 + rootOffset + rootSize <= bytes.count else {
            throw IconKitError("the .DS_Store header is inconsistent")
        }
        let root = 4 + rootOffset
        let count = Int(reader.uint32(at: root))
        let addresses = (0..<count).map { reader.uint32(at: root + 8 + 4 * $0) }
        var position = root + 8 + 4 * ((count + 255) / 256 * 256)
        let entries = Int(reader.uint32(at: position))
        position += 4
        var directory: [String: Int] = [:]
        for _ in 0..<entries {
            let length = Int(bytes[position])
            let name = String(decoding: bytes[(position + 1)..<(position + 1 + length)], as: UTF8.self)
            directory[name] = Int(reader.uint32(at: position + 1 + length))
            position += 5 + length
        }
        guard let masterNumber = directory["DSDB"], masterNumber < addresses.count else {
            throw IconKitError("the .DS_Store has no DSDB entry")
        }
        func blockStart(_ number: Int) throws -> Int {
            guard number < addresses.count else { throw IconKitError("block \(number) does not exist") }
            let address = Int(addresses[number])
            let start = 4 + (address & ~0x1F), size = 1 << (address & 0x1F)
            guard start + size <= bytes.count else { throw IconKitError("block \(number) runs past the end of the file") }
            return start
        }
        let master = try blockStart(masterNumber)
        let rootNode = Int(reader.uint32(at: master))

        var records: [Record] = []
        func readNode(_ number: Int, depth: Int) throws {
            guard depth < 32 else { throw IconKitError("the .DS_Store tree is too deep") }
            var p = try blockStart(number)
            let rightmost = Int(reader.uint32(at: p)), count = Int(reader.uint32(at: p + 4))
            p += 8
            for _ in 0..<count {
                if rightmost != 0 {
                    try readNode(Int(reader.uint32(at: p)), depth: depth + 1)
                    p += 4
                }
                records.append(try reader.record(at: &p))
            }
            if rightmost != 0 { try readNode(rightmost, depth: depth + 1) }
        }
        try readNode(rootNode, depth: 0)
        return records
    }

    private struct Reader {
        let bytes: [UInt8]

        func uint32(at offset: Int) -> UInt32 {
            bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
        }

        func uint64(at offset: Int) -> UInt64 {
            bytes[offset..<(offset + 8)].reduce(0) { $0 << 8 | UInt64($1) }
        }

        func utf16(at offset: Int, units: Int) -> String {
            let values = (0..<units).map { UInt16(bytes[offset + 2 * $0]) << 8 | UInt16(bytes[offset + 2 * $0 + 1]) }
            return String(decoding: values, as: UTF16.self)
        }

        func code(at offset: Int) -> String {
            String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
        }

        func record(at p: inout Int) throws -> Record {
            let length = Int(uint32(at: p))
            let name = utf16(at: p + 4, units: length)
            p += 4 + 2 * length
            let property = code(at: p), type = code(at: p + 4)
            p += 8
            let value: Value
            switch type {
            case "long": value = .long(uint32(at: p)); p += 4
            case "shor": value = .short(UInt16(truncatingIfNeeded: uint32(at: p))); p += 4
            case "bool": value = .bool(bytes[p] != 0); p += 1
            case "type": value = .type(self.code(at: p)); p += 4
            case "blob":
                let size = Int(uint32(at: p))
                value = .blob(Data(bytes[(p + 4)..<(p + 4 + size)])); p += 4 + size
            case "ustr":
                let units = Int(uint32(at: p))
                value = .ustr(utf16(at: p + 4, units: units)); p += 4 + 2 * units
            case "comp": value = .comp(uint64(at: p)); p += 8
            case "dutc": value = .dutc(uint64(at: p)); p += 8
            default: throw IconKitError("unknown record type '\(type)' for \(name) \(property)")
            }
            return Record(name: name, code: property, value: value)
        }
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: (0..<4).reversed().map { UInt8((value >> (8 * UInt32($0))) & 0xFF) })
    }

    mutating func appendUInt64(_ value: UInt64) {
        append(contentsOf: (0..<8).reversed().map { UInt8((value >> (8 * UInt64($0))) & 0xFF) })
    }

    mutating func replace(at offset: Int, with data: Data) {
        replaceSubrange(offset..<(offset + data.count), with: data)
    }
}
