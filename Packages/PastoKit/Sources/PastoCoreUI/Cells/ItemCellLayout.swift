import CoreGraphics
import PastoUI

/// The vertical structure of an item card for one density.
nonisolated struct ItemCellLayout: Sendable, Equatable {
    /// Where the body starts, from the card's top edge.
    var contentTopOffset: CGFloat
    var headerHeight: CGFloat

    /// In the compact density a card whose content is full size starts its body at the top edge
    /// and lets the header float over it.
    init(sizeClass: SizeClass, isCompactContentFullSize: Bool) {
        headerHeight = Self.headerHeight(for: sizeClass)
        contentTopOffset = sizeClass == .compact && isCompactContentFullSize ? 0 : headerHeight
    }

    init(contentTopOffset: CGFloat, headerHeight: CGFloat) {
        self.contentTopOffset = contentTopOffset
        self.headerHeight = headerHeight
    }

    static func headerHeight(for sizeClass: SizeClass) -> CGFloat {
        switch sizeClass {
        case .large: 56
        case .regular: 52
        case .small: 48
        case .compact: 36
        }
    }

    /// The layout part-way through a density transition: both values move linearly.
    static func blend(from source: ItemCellLayout, to destination: ItemCellLayout, progress: Double) -> ItemCellLayout {
        ItemCellLayout(
            contentTopOffset: .blend(from: source.contentTopOffset, to: destination.contentTopOffset, progress: progress),
            headerHeight: .blend(from: source.headerHeight, to: destination.headerHeight, progress: progress)
        )
    }
}

nonisolated extension CGFloat {
    /// Linear interpolation, `progress` 0 giving `source` and 1 giving `destination`.
    static func blend(from source: CGFloat, to destination: CGFloat, progress: Double) -> CGFloat {
        (1 - progress) * source + progress * destination
    }

    /// One step of the density transition's "towards the target" rule: applied on every
    /// frame to the value the view currently has, so it closes in faster at the start.
    func approaching(_ target: CGFloat, progress: Double) -> CGFloat {
        .blend(from: self, to: target, progress: progress)
    }
}
