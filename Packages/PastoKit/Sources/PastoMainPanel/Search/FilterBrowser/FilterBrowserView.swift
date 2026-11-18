import AppKit
import PastoSearch
import SwiftUI

/// The filter browser: every filter there is to choose from, by type, in a three-column grid.
struct FilterBrowserView: View {
    private typealias Metrics = SearchMetrics.Browser

    let model: FilterBrowserModel

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: Metrics.minimumColumnWidth), spacing: Metrics.columnSpacing),
        count: Metrics.columnCount
    )

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(indexedSections, id: \.section.id) { indexed in
                        sectionView(indexed.section, firstIndex: indexed.firstIndex)
                    }
                }
                .padding(.horizontal, Metrics.horizontalPadding)
            }
            .contentMargins(.vertical, Metrics.scrollIndicatorMargin, for: .scrollIndicators)
            .onChange(of: model.highlightedEntryID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(width: Metrics.width)
        .frame(minHeight: Metrics.minimumHeight, maxHeight: Metrics.maximumHeight)
    }

    /// Each section with the index its first entry has in the browser's reading order, which is
    /// what the keyboard highlight counts in.
    private var indexedSections: [(section: FilterBrowserSection, firstIndex: Int)] {
        var firstIndex = 0
        return model.sections.map { section in
            defer { firstIndex += section.entries.count }
            return (section, firstIndex)
        }
    }

    private func sectionView(_ section: FilterBrowserSection, firstIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(SearchStrings.sectionTitle(for: section.type))
                .font(.callout.bold())
                .foregroundStyle(.secondary)
                .padding(.vertical, Metrics.titleVerticalPadding)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .center, spacing: Metrics.rowSpacing) {
                ForEach(Array(section.entries.enumerated()), id: \.element.id) { offset, entry in
                    entryButton(entry, isHighlighted: firstIndex + offset == model.highlightedIndex)
                        .id(entry.id)
                }
            }
        }
        .padding(.bottom, Metrics.sectionBottomPadding)
    }

    private func entryButton(_ entry: FilterBrowserSection.Entry, isHighlighted: Bool) -> some View {
        let isSelected = if case .filter(_, true) = entry { true } else { false }
        return Button {
            // ⌘ keeps the browser open, to choose several filters in a row.
            model.activate(entry, keepsOpen: NSEvent.modifierFlags.contains(.command))
        } label: {
            // As wide as its column, its content at the leading edge: 132 pt with three columns.
            entryLabel(entry)
                .padding(.horizontal, Metrics.itemHorizontalPadding)
                .padding(.vertical, Metrics.itemVerticalPadding)
                .frame(maxWidth: .infinity, minHeight: Metrics.itemHeight, maxHeight: Metrics.itemHeight, alignment: .leading)
        }
        .buttonStyle(FilterBrowserEntryStyle(isSelected: isSelected))
        // A filter the query has reads as selected, not only as a filled capsule.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay {
            if isHighlighted {
                Capsule(style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: Metrics.keyboardHighlightWidth)
                    .padding(-Metrics.keyboardHighlightOutset)
            }
        }
    }

    @ViewBuilder
    private func entryLabel(_ entry: FilterBrowserSection.Entry) -> some View {
        switch entry {
        case .filter(let suggestion, _):
            HStack(spacing: Metrics.itemSpacing) {
                // The name says it; a symbol would add its own name to the button's.
                iconView(model.icon(suggestion.filter))
                    .accessibilityHidden(true)
                Text(suggestion.title).font(.body).lineLimit(1)
            }
        case .disclosure(_, let isExpanded):
            HStack(spacing: Metrics.disclosureSpacing) {
                Image(systemName: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                    .resizable()
                    .frame(width: Metrics.disclosureIconSide, height: Metrics.disclosureIconSide)
                    .accessibilityHidden(true)
                Text(isExpanded ? SearchStrings.less : SearchStrings.more).font(.body)
            }
        }
    }

    /// Symbols and application icons are stretched to fill the square, without keeping their
    /// proportions; only the pinboard dot keeps its own size inside it.
    @ViewBuilder
    private func iconView(_ icon: SearchFilterIcon) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .resizable()
                .frame(width: Metrics.itemIconSide, height: Metrics.itemIconSide)
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: Metrics.itemIconSide, height: Metrics.itemIconSide)
            }
        case .pinboardDot(let color):
            Circle()
                .fill(Color(nsColor: color.displayColor))
                .frame(width: Metrics.pinboardDotSide, height: Metrics.pinboardDotSide)
                .frame(width: Metrics.itemIconSide, height: Metrics.itemIconSide)
        case .none:
            EmptyView()
        }
    }
}

/// A capsule that fills with the accent colour when its filter is in the query and darkens
/// while pressed, behind the text and the icon.
private struct FilterBrowserEntryStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let restingFill = (colorScheme == .dark ? Color.white : .black).opacity(SearchMetrics.Browser.restingFillOpacity)
        return configuration.label
            .foregroundStyle(isSelected ? Color.white : Color(nsColor: .labelColor))
            .background {
                Capsule(style: .continuous).fill(isSelected ? Color.accentColor : restingFill)
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(SearchMetrics.Browser.pressedFillOpacity))
                    .opacity(configuration.isPressed ? 1 : 0)
            }
            .contentShape(Capsule(style: .continuous))
    }
}
