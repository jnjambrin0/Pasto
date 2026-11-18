import AppKit

/// The blurred material behind the small capsules that sit on top of a card's content: the
/// shortcut indicator and the image size badge.
final class BackdropView: NSVisualEffectView {
    init() {
        super.init(frame: .zero)
        material = .menu
        blendingMode = .withinWindow
        state = .active
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BackdropView is created in code")
    }
}
