import CoreGraphics

/// How much room an item card has. It is decided by the card's side, which follows the panel's
/// height.
public nonisolated enum SizeClass: Int, Sendable, CaseIterable {
    case large
    case regular
    case small
    case compact

    public init(cellSide: CGFloat) {
        switch cellSide {
        case 280...: self = .large
        case 240...: self = .regular
        case 200...: self = .small
        default: self = .compact
        }
    }
}

/// A view whose internal layout depends on the size class and can blend between two of them.
public protocol SizeClassTransitionable: AnyObject {
    /// `progress` runs from 0 (laid out for `source`) to 1 (laid out for `destination`).
    func transition(from source: SizeClass, to destination: SizeClass, progress: Double)
}
