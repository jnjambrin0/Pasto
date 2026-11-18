import Foundation

extension Array {
    /// The array with the elements at `offsets` taken out and put back together, in the order
    /// they had, in front of the element that was at `destination` (at the end when
    /// `destination` is the count).
    func moving(fromOffsets offsets: IndexSet, toOffset destination: Int) -> [Element] {
        let destination = Swift.min(Swift.max(destination, 0), count)
        let moved = offsets.map { self[$0] }
        var result = indices.filter { !offsets.contains($0) }.map { self[$0] }
        // The elements taken out from before the destination no longer push it to the right.
        result.insert(contentsOf: moved, at: destination - offsets.count(in: 0..<destination))
        return result
    }
}
