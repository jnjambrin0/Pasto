import PastoCore
import SwiftUI

/// The card of one row, built from the row's item.
///
/// Building a card's content parses formatted text, so it should not happen every time the list
/// redraws — which the pointer moving from row to row makes it do. Compared by what it shows,
/// this view is only rebuilt when that changes. The actions are left out of the comparison: they
/// stand for the row, which does not change.
struct StackRowCard: View, Equatable {
    let item: Item
    let isPlainText: Bool
    let isLinkPreviewsOn: Bool
    let showsDeleteButton: Bool
    let onPaste: () -> Void
    let onDelete: () -> Void

    var body: some View {
        StackCard(
            content: StackCardContent(item: item, isPlainText: isPlainText, isLinkPreviewsOn: isLinkPreviewsOn),
            showsDeleteButton: showsDeleteButton,
            onPaste: onPaste,
            onDelete: onDelete
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
            && lhs.isPlainText == rhs.isPlainText
            && lhs.isLinkPreviewsOn == rhs.isLinkPreviewsOn
            && lhs.showsDeleteButton == rhs.showsDeleteButton
    }
}
