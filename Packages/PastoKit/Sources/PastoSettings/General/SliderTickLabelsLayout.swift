import SwiftUI

/// Places one name under each tick of a slider as wide as the layout, centred on its tick. A name
/// that would stick out past either end is pulled back in.
nonisolated struct SliderTickLabelsLayout: Layout {
    /// How far the first and last ticks sit from the slider's ends.
    let tickInset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gaps = CGFloat(max(subviews.count - 1, 1))
        let tickSpacing = (bounds.width - 2 * tickInset) / gaps
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let tick = bounds.minX + tickInset + CGFloat(index) * tickSpacing
            let x = min(max(tick - size.width / 2, bounds.minX), bounds.maxX - size.width)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
        }
    }
}
