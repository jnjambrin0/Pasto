import AppKit

/// The panel's Liquid Glass backdrop. Content goes inside `contentView` so the system can treat
/// it as sitting on the glass.
///
/// Style and tint are left at the system defaults.
public final class BackgroundEffectView: NSView {
    public let contentView = NSView(frame: .zero)
    private let glassView = NSGlassEffectView(frame: .zero)

    public init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        glassView.cornerRadius = cornerRadius
        glassView.contentView = contentView
        glassView.autoresizingMask = [.width, .height]
        addSubview(glassView)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("BackgroundEffectView is created in code")
    }
}
