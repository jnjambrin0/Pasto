import SwiftUI

/// The content of the stack's window: the rounded glass panel, anchored to the top of a
/// transparent window that is as tall as the panel may ever get.
struct StackView: View {
    let model: StackModel
    let state: StackPanelState
    let dragging: StackRowDragging

    /// The height of the rows; unknown until they have been laid out once.
    @State private var rowsHeight: CGFloat?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StackMetrics.Panel.cornerRadius, style: .continuous)
    }

    /// The room the rows have under the header.
    private var availableRowsHeight: CGFloat {
        state.heightLimit - StackMetrics.Header.height
    }

    var body: some View {
        ZStack(alignment: .top) {
            StackRowList(
                rowIDs: model.rows.map(\.id),
                showsScroller: rowsHeight.map { $0 > availableRowsHeight } ?? false,
                state: state
            ) {
                StackRowsView(model: model, state: state, dragging: dragging)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height, action: rowsHeightChanged)
            }
            // The panel is as tall as its rows, up to the limit; beyond it, the list scrolls.
            .frame(height: rowsHeight.map { min(availableRowsHeight, $0) + StackMetrics.Header.height })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.listFrame = $0 }

            StackHeader(model: model)
        }
        .frame(width: StackMetrics.Panel.width)
        .clipShape(shape)
        .background { StackPanelBackground() }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.panelFrame = $0 }
        .animation(StackMetrics.Motion.layout, value: model.rows.map(\.id))
        .animation(StackMetrics.Motion.layout, value: state.dropIndex)
        .padding(StackMetrics.Panel.margin)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    /// The first measurement only sizes the panel; later ones animate it to its new height.
    private func rowsHeightChanged(_ height: CGFloat) {
        if rowsHeight == nil {
            rowsHeight = height
        } else {
            withAnimation(StackMetrics.Motion.layout) { rowsHeight = height }
        }
    }
}
