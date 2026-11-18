import AppKit

/// The header over a pane, in the title bar area: the pane's title on the window's background.
final class PaneTitleView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init() {
        super.init(frame: .zero)
        material = .windowBackground
        blendingMode = .withinWindow

        label.font = .systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SettingsMetrics.headerHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsMetrics.headerTitleInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -SettingsMetrics.headerTitleInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
