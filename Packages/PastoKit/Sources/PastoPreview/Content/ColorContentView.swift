import AppKit
import PastoCore
import PastoCoreUI
import PastoUI

/// The preview of a colour: the colour itself with its hexadecimal value in the middle, and its
/// RGB, HSL and HSB notations underneath. Editing is done in the system colour panel, which
/// opens beside the window.
final class ColorContentView: LayerBackedView, ItemContentView, FooterProviding, EditableContent {
    let footer = FooterView()
    var onCanCommitChange: ((Bool) -> Void)?
    var editingToolbar: NSView? { nil }

    private let environment: PreviewEnvironment
    private let itemID: ItemID
    private let codeLabel = NSTextField(labelWithString: "")
    /// The colour the item holds.
    private var storedColor: ColorCode
    /// The colour on screen: the stored one, or the panel's while editing.
    private var shownColor: ColorCode
    private var isEditing = false

    init(item: Item, environment: PreviewEnvironment) {
        self.environment = environment
        itemID = item.id
        storedColor = Self.color(of: item)
        shownColor = storedColor
        super.init(frame: .zero)

        let size = PreviewMetrics.colorCodeFontSize
        codeLabel.font = .userFixedPitchFont(ofSize: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        codeLabel.alignment = .center
        codeLabel.textColor = ItemPresentation.primaryTextColor
        addSubview(codeLabel)
        show(storedColor)
    }

    /// Black for an item whose preview is not a colour.
    private static func color(of item: Item) -> ColorCode {
        guard case .color(let preview) = item.preview else { return ColorCode(rawValue: 0) }
        return ColorCode(truncating: preview.colorCode).withoutAlpha
    }

    func update(with item: Item) {
        storedColor = Self.color(of: item)
        if !isEditing {
            show(storedColor)
        }
    }

    override func layout() {
        super.layout()
        let size = codeLabel.intrinsicContentSize
        let textRect = NSRect(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        // The intrinsic size is that of the text; the field needs the margins of its cell too.
        codeLabel.frame = codeLabel.frame(forAlignmentRect: textRect)
    }

    override func updateLayerColors() {
        layer?.backgroundColor = NSColor(shownColor).cgColor
    }

    private func show(_ color: ColorCode) {
        shownColor = color
        codeLabel.stringValue = color.hexString
        // Dark text on a light colour and light text on a dark one, as on the card.
        codeLabel.appearance = NSAppearance(named: color.isLight ? .aqua : .darkAqua)
        needsLayout = true
        needsDisplay = true
        showFooter()
    }

    private func showFooter() {
        let components = NSColor(shownColor).usingColorSpace(.deviceRGB) ?? NSColor(shownColor)
        let formats = ColorFormats(
            red: components.redComponent, green: components.greenComponent, blue: components.blueComponent
        )
        let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
        let pairs = formats.entries.map { name, value in
            let nameLabel = NSTextField(labelWithString: name)
            nameLabel.font = .preferredFont(forTextStyle: .body)
            nameLabel.textColor = ItemPresentation.primaryTextColor
            let valueLabel = NSTextField(labelWithString: value)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: bodySize, weight: .regular)
            valueLabel.textColor = ItemPresentation.secondaryTextColor

            let pair = NSStackView(views: [nameLabel, valueLabel])
            pair.spacing = PreviewMetrics.colorFormatSpacing
            return pair
        }
        // The trailing spacer keeps the notations at the leading edge.
        let row = NSStackView(views: pairs + [NSView(frame: .zero)])
        row.spacing = PreviewMetrics.colorFormatsSpacing
        footer.setContent(row)
    }

    // MARK: - Colour panel

    private var panel: NSColorPanel { .shared }

    /// Opens the panel beside the window the view is in.
    private func showPanel() {
        guard let window else { return }
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.standardWindowButton(.closeButton)?.isEnabled = false
        panel.showsAlpha = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        panel.animationBehavior = .none
        panel.color = NSColor(storedColor)

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelColorDidChange), name: NSColorPanel.colorDidChangeNotification, object: panel
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window
        )
        panel.makeKeyAndOrderFront(nil)

        if let screen = NSScreen.main {
            panel.setFrameOrigin(ColorPanelPlacement.origin(
                windowFrame: window.frame, panelSize: panel.frame.size, screenWidth: screen.frame.width
            ))
        }
    }

    private func hidePanel() {
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
    }

    @objc private func panelColorDidChange() {
        guard let color = ColorCode(opaque: panel.color) else { return }
        show(color)
        onCanCommitChange?(color != storedColor)
    }

    /// The window can be closed while editing, and the panel must not outlive it.
    @objc private func windowWillClose() {
        isEditing = false
        hidePanel()
    }

    // MARK: - EditableContent

    func beginEditing() {
        isEditing = true
        onCanCommitChange?(false)
    }

    /// The panel is placed beside the window, so it waits until the view is in one.
    func focusEditor() {
        showPanel()
    }

    func cancelEditing() {
        isEditing = false
        hidePanel()
        show(storedColor)
    }

    func commitEditing() {
        isEditing = false
        hidePanel()
        environment.replaceContent(of: itemID, with: ItemContentComposer.color(shownColor))
        storedColor = shownColor
    }
}

extension NSColor {
    /// An opaque sRGB colour.
    convenience init(_ code: ColorCode) {
        self.init(srgbRed: code.red, green: code.green, blue: code.blue, alpha: 1)
    }
}

extension ColorCode {
    /// The colour without its alpha, which a colour item does not have. `nil` for colours
    /// with no RGB form, such as patterns.
    init?(opaque color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        self = ColorCode(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent).withoutAlpha
    }

    /// The same colour as `0x00RRGGBB`, so that two colour items compare by their colour alone.
    var withoutAlpha: ColorCode {
        ColorCode(rawValue: rawValue & 0xFFFFFF)
    }
}
