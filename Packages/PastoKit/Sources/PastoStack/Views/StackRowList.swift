import SwiftUI

/// The scrolling part of the panel. It runs under the header: its content and its scroller start
/// below it, and the content fades out as it scrolls up behind it.
struct StackRowList<Content: View>: View {
    /// The rows, top to bottom.
    let rowIDs: [StackRow.ID]
    /// The scroller only shows when the rows do not fit.
    let showsScroller: Bool
    let state: StackPanelState
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                content
            }
            .contentMargins(.top, StackMetrics.Header.height)
            .contentMargins(.bottom, StackMetrics.List.scrollerBottomInset, for: .scrollIndicators)
            .scrollIndicators(showsScroller ? .automatic : .never)
            .scrollBounceBehavior(.basedOnSize)
            .mask { headerFade }
            .onChange(of: rowIDs) { old, new in
                // After a paste with the list scrolled, the row that ⌘V takes next comes into view.
                guard new.count < old.count, let first = new.first, first != old.first else { return }
                // Its card has its new frame once this change has been laid out.
                Task { revealIfUnderHeader(first, with: proxy) }
            }
        }
    }

    private func revealIfUnderHeader(_ rowID: StackRow.ID, with proxy: ScrollViewProxy) {
        guard state.hitTest.isScrolledUnderHeader(rowID) else { return }
        withAnimation(StackMetrics.Motion.revealFirstRow) {
            proxy.scrollTo(rowID, anchor: .top)
        }
    }

    private var headerFade: some View {
        let fadeStart = StackMetrics.Header.height - StackMetrics.List.fadeStartAboveHeader
        let fadeHeight = StackMetrics.List.fadeStartAboveHeader + StackMetrics.List.fadeEndBelowHeader
        return VStack(spacing: 0) {
            Color.clear.frame(height: fadeStart)
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: fadeHeight)
            Color.black
        }
    }
}
