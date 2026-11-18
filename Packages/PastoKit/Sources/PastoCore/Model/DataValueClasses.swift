import Foundation

/// Numbers pieces of data by value: equal bytes, same number. For the stand-ins of
/// `BinaryPropertyListLayout`, which must be equal exactly where the data is.
///
/// Not a dictionary keyed by `Data`: `Data`'s hash reads every byte, 0.4 s for the 300 MB of a
/// large copy. The key here is the length and the bytes at both ends, and only pieces that share
/// it are compared — which stops at the first byte that differs.
struct DataValueClasses {
    private struct Fingerprint: Hashable {
        var count: Int
        var ends: Int

        /// How many bytes at each end the fingerprint reads.
        static let span = 64

        init(_ data: Data) {
            count = data.count
            var hasher = Hasher()
            data.withUnsafeBytes { bytes in
                let head = UnsafeRawBufferPointer(rebasing: bytes.prefix(Self.span))
                let tail = UnsafeRawBufferPointer(rebasing: bytes.suffix(Self.span))
                hasher.combine(bytes: head)
                hasher.combine(bytes: tail)
            }
            ends = hasher.finalize()
        }
    }

    private var classesByFingerprint: [Fingerprint: [Int]] = [:]
    /// One piece of data per class, by number.
    private(set) var values: [Data] = []

    /// The number of the class `data` belongs to, a new one if no piece so far is equal to it.
    mutating func number(of data: Data) -> Int {
        let fingerprint = Fingerprint(data)
        if let match = classesByFingerprint[fingerprint]?.first(where: { values[$0] == data }) {
            return match
        }
        values.append(data)
        classesByFingerprint[fingerprint, default: []].append(values.count - 1)
        return values.count - 1
    }
}
