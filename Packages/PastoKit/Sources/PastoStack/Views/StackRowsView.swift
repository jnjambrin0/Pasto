import AppKit
import SwiftUI

/// The stack's rows, top to bottom, or a hint while there are none.
struct StackRowsView: View {
    let model: StackModel
    let state: StackPanelState
    let dragging: StackRowDragging

    /// The application a paste would go to, for the context menu.
    @State private var pasteTargetName = Self.frontmostApplicationName()

    var body: some View {
        VStack(spacing: StackMetrics.List.cardSpacing) {
            if model.showsFirstUseHint {
                firstUseHint
            }
            if model.rows.isEmpty {
                emptyState.transition(.opacity)
            }
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                card(for: row, at: index)
            }
        }
        // Something dragged in to go after the last row opens its gap at the bottom.
        .padding(.bottom, !model.rows.isEmpty && state.dropIndex == model.rows.count ? StackMetrics.List.dropGap : 0)
        .padding(.horizontal, StackMetrics.List.horizontalPadding)
        .padding(.bottom, StackMetrics.List.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(StackMetrics.Motion.layout, value: model.rows.map(\.id))
        .animation(StackMetrics.Motion.layout, value: state.dropIndex)
        .onChange(of: model.rows.map(\.id)) { _, rowIDs in
            state.cardFrames = state.cardFrames.filter { rowIDs.contains($0.key) }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            pasteTargetName = application?.localizedName ?? Self.frontmostApplicationName()
        }
    }

    private func card(for row: StackRow, at index: Int) -> some View {
        StackRowCard(
            item: row.item,
            isPlainText: model.isPlainTextOn,
            isLinkPreviewsOn: model.isLinkPreviewsOn,
            showsDeleteButton: state.highlightedRowID == row.id,
            onPaste: { model.paste(row.id) },
            onDelete: { model.removeRow(row.id) }
        )
        .equatable()
        // While its card is off the list, the row keeps its slot.
        .opacity(state.liftedRowID == row.id ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.cardFrames[row.id] = $0 }
        // The drag opens its session on its first step and ignores the rest.
        .gesture(
            DragGesture(minimumDistance: StackMetrics.Drag.minimumDistance)
                .onChanged { _ in dragging.beginDragging(row) }
        )
        // Something dragged in to go before this row opens its gap above it.
        .padding(.top, state.dropIndex == index ? StackMetrics.List.dropGap : 0)
        .transition(AnyTransition(StackCardTransition()).animation(StackMetrics.Motion.cardTransition))
        .contextMenu {
            Button(StackStrings.paste(to: pasteTargetName)) { model.paste(row.id) }
            Button(StackStrings.delete) { model.removeRow(row.id) }
        }
        // Without a mouse: the menu's commands, and moving a row, which otherwise takes a drag.
        // Pasting is the card's default action.
        .accessibilityActions {
            Button(StackStrings.delete) { model.removeRow(row.id) }
            if index > 0 {
                Button(StackStrings.moveUp) { model.move(row.id, to: index - 1) }
            }
            if index < model.rows.count - 1 {
                Button(StackStrings.moveDown) { model.move(row.id, to: index + 1) }
            }
        }
    }

    /// One line, the first time a stack opens, on what it is for.
    private var firstUseHint: some View {
        Label(StackStrings.firstUseHint, systemImage: "info.circle")
            .font(.system(size: StackMetrics.List.firstUseHintFontSize))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: StackMetrics.Card.width, alignment: .leading)
    }

    /// The hint reserves the height of a single line, so an empty panel is always as tall; the
    /// message is laid over it from the top.
    private var emptyState: some View {
        emptyStateText(" ")
            .hidden()
            .overlay(alignment: .top) {
                emptyStateText(StackStrings.emptyState)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }

    private func emptyStateText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: StackMetrics.List.emptyStateFontSize))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .padding(StackMetrics.List.emptyStatePadding)
            .frame(width: StackMetrics.Card.width)
    }

    private static func frontmostApplicationName() -> String {
        NSWorkspace.shared.menuBarOwningApplication?.localizedName ?? StackStrings.currentApplication
    }
}
