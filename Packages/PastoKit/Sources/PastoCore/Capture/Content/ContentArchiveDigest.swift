import CryptoKit
import Foundation

/// The MD5 of the keyed archive that content of no known kind is hashed as (`ItemChecksum`),
/// computed without building the archive: built whole, it would be another copy of the content,
/// and more, held in memory at once.
///
/// `NSKeyedArchiver` archives the same arrays with a small stand-in in place of every piece of
/// data; the stand-ins are then swapped for the real bytes as the archive is fed to the hash
/// (`BinaryPropertyListLayout`). The archive is the one the archiver would have made of the real
/// data, byte for byte, because the stand-ins are treated as the data would be:
/// - the archiver writes one object per distinct object it is given: each piece of data is
///   bridged as the archive bridges it, and pieces that bridge to one object share a stand-in;
/// - the property list writer stores equal data once: equal pieces get equal stand-ins and
///   different pieces different ones;
/// - empty data is left as it is (its bridged form is a shared object).
enum ContentArchiveDigest {
    /// - Returns: `nil` when there are no items, or the archiver cannot archive them.
    static func digest(of items: [PasteboardItemSnapshot]) -> Insecure.MD5Digest? {
        guard !items.isEmpty else { return nil }
        var standIns = StandIns()
        let representation = items.map { item in
            item.types.map { [$0 as NSString, standIns.standIn(for: item.dataByType[$0] ?? Data())] as NSArray } as NSArray
        } as NSArray
        guard let archive = try? NSKeyedArchiver.archivedData(withRootObject: representation, requiringSecureCoding: true),
              let layout = try? BinaryPropertyListLayout(archive, offsetWidth: .powerOfTwo)
        else { return nil }

        let substitutes = layout.dataObjects.map { standIns.data(standingIn: $0) }
        var sink = Sink()
        layout.write(substituting: { substitutes[$0] }, to: &sink)
        return sink.hash.finalize()
    }

    private struct StandIns {
        /// What the archive would have been given, kept alive so that no identity is reused.
        private var bridged: [NSData] = []
        private var standInByObject: [ObjectIdentifier: NSData] = [:]
        private var classes = DataValueClasses()

        mutating func standIn(for data: Data) -> NSData {
            let object = data as NSData
            guard !data.isEmpty else { return object }
            if let standIn = standInByObject[ObjectIdentifier(object)] {
                return standIn
            }
            bridged.append(object)
            let index = UInt64(classes.number(of: data))
            // A new object for every one the archive is given, equal to the others of its value.
            let standIn = withUnsafeBytes(of: index.littleEndian) { NSData(bytes: $0.baseAddress, length: $0.count) }
            standInByObject[ObjectIdentifier(object)] = standIn
            return standIn
        }

        /// The data a stand-in took the place of; empty data stands for itself.
        func data(standingIn standIn: Data) -> Data {
            guard standIn.count == MemoryLayout<UInt64>.size else { return standIn }
            let index = standIn.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            return index < UInt64(classes.values.count) ? classes.values[Int(index)] : standIn
        }
    }

    private struct Sink: BinaryPropertyListLayout.Sink {
        var hash = Insecure.MD5()

        mutating func write(_ bytes: UnsafeRawBufferPointer) {
            hash.update(bufferPointer: bytes)
        }
    }
}
