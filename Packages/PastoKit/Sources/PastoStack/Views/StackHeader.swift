import AppKit
import SwiftUI

/// The top band of the panel: its name and its buttons.
struct StackHeader: View {
    /// The menu bar glyph of the app, in its asset catalogue: the panel is named after it.
    private static let titleGlyphName = "StatusItemIcon"

    let model: StackModel

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            title
            Spacer(minLength: 0)
            buttons
        }
        .padding(StackMetrics.Header.padding)
        .frame(height: StackMetrics.Header.height)
    }

    private var title: some View {
        HStack(spacing: StackMetrics.Header.titleSpacing) {
            // A menu bar glyph leaves a margin around its drawing; it is drawn larger than the
            // room it takes so that the drawing itself fills that room.
            Image(Self.titleGlyphName, bundle: .main)
                .renderingMode(.template)
                .resizable()
                .frame(width: StackMetrics.Header.titleGlyphSide, height: StackMetrics.Header.titleGlyphSide)
                .frame(width: StackMetrics.Header.titleGlyphFrameSide, height: StackMetrics.Header.titleGlyphFrameSide)
                .accessibilityHidden(true)
            Text(StackStrings.title)
                .font(.title3.weight(.medium))
                .accessibilityAddTraits(.isHeader)
        }
        .foregroundStyle(Color(nsColor: .labelColor))
        .padding(.horizontal, StackMetrics.Header.titleHorizontalPadding)
    }

    private var buttons: some View {
        HStack(spacing: StackMetrics.Header.buttonSpacing) {
            // Undo is only there while there is something to undo.
            if !model.undoSteps.isEmpty {
                StackHeaderButton(
                    symbolName: "arrow.uturn.backward",
                    label: StackStrings.undo,
                    behavior: .action { model.undo() }
                )
                .transition(StackHeaderButtonTransition())
            }
            StackHeaderButton(
                symbolName: "ellipsis",
                label: StackStrings.more,
                behavior: .menu { StackMenu.make(for: model) }
            )
            StackHeaderButton(
                symbolName: "xmark",
                label: StackStrings.close,
                behavior: .action { model.onCloseRequest?() }
            )
        }
        .animation(StackMetrics.Motion.layout, value: model.undoSteps.isEmpty)
    }
}
