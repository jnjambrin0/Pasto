import SwiftUI

/// A box of rows with a separator between each two, and an optional title above. The box has no
/// border: only a faint fill.
struct SettingsSection<Content: View>: View {
    var title: String?
    var subtitle: String?
    /// Off for content that runs to the box's edges, like a list: it then sits tight and is
    /// clipped to the box.
    var isPadded = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionTitleSpacing) {
            if let title {
                SettingsRowLabel(title: title, subtitle: subtitle)
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, SettingsMetrics.sectionTitleInset)
            }
            if isPadded {
                rows.padding(SettingsMetrics.boxPadding).background(fill, in: box)
            } else {
                rows.background(fill, in: box).clipShape(box)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: isPadded ? SettingsMetrics.boxSpacing : 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Divider()
                    }
                    row
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var fill: Color {
        Color.primary.opacity(SettingsMetrics.boxFillOpacity)
    }

    private var box: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsMetrics.boxCornerRadius, style: .circular)
    }
}
