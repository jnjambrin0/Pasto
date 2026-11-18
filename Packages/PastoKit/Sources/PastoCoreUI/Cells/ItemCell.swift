import AppKit
import PastoUI

/// A clipboard item's card: header, body and the shortcut indicator on top. Each kind of content
/// has its own subclass, which fills the body; get the class for an item from `ItemCellFactory`.
///
/// A cell shows whatever `configure(with:sizeClass:environment:)` last gave it and fetches
/// nothing else. Images arrive a moment later, decoded off the main thread.
open class ItemCell: BaseCell, SizeClassTransitionable {
    /// Called when the user renames the card and the title actually changes: the new title, or
    /// `nil` when it was cleared and the card goes back to showing its type's name.
    public var onRename: ((String?) -> Void)?

    /// The number shown while the quick paste modifier is held. The collection updates it when
    /// cards move without reconfiguring them.
    public var quickPasteIndex: Int? {
        get { shortcutView.quickPasteIndex }
        set { shortcutView.quickPasteIndex = newValue }
    }

    /// Where subclasses put their content. It starts below the header, or at the card's top
    /// edge when the content is full size in the compact density.
    let bodyView = CardView(frame: .zero)

    private let headerView = HeaderView(frame: .zero)
    private let shortcutView = ShortcutIndicatorView(frame: .zero)

    /// What the card is showing.
    private(set) var model: ItemCellModel?
    /// The density the card is laid out for, or moving to.
    private var sizeClass = SizeClass.small
    private var layoutValues = ItemCellLayout(sizeClass: .small, isCompactContentFullSize: false)

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Back to front. The indicator stays above whatever the body shows.
        contentView.addSubview(bodyView)
        contentView.addSubview(headerView)
        contentView.addSubview(shortcutView)

        headerView.titleLabel.onCommitEditing = { [weak self] text in
            self?.commitTitle(text)
        }
    }

    // MARK: - For subclasses

    /// Whether the content takes the whole card in the compact density, with the header on top
    /// of it.
    var isCompactContentFullSize: Bool { false }

    /// How the header stays readable over full-size content; `nil` for the default.
    var preferredCompactHeaderStyle: HeaderLayout.CompactStyle? { nil }

    /// Shows the model's content. Called before the header is configured, so the two properties
    /// above may depend on what was just shown.
    func configureContent(with model: ItemCellModel, environment: ItemCellEnvironment) {}

    /// Sets the density-dependent parts of the content for `sizeClass`, without animation.
    func applyContentLayout(for sizeClass: SizeClass) {}

    /// Moves the density-dependent parts of the content towards `destination`.
    func transitionContent(to destination: SizeClass, progress: Double) {}

    /// Positions the content inside the body, whose bounds are `bounds`.
    func layoutContent(in bounds: CGRect) {}

    /// Cancels work in progress for the item being shown.
    func cancelPendingWork() {}

    /// Tells the card that `preferredCompactHeaderStyle` changed after it was configured: the
    /// content turned out otherwise than it looked, like a link image that does not decode.
    func compactHeaderStyleDidChange() {
        headerView.setCompactStyle(preferredCompactHeaderStyle ?? .transparent, sizeClass: sizeClass)
    }

    // MARK: - Configuration

    /// Shows an item. `sizeClass` is the strip's current density.
    public func configure(with model: ItemCellModel, sizeClass: SizeClass, environment: ItemCellEnvironment) {
        self.model = model
        self.sizeClass = sizeClass

        configureContent(with: model, environment: environment)
        applyContentLayout(for: sizeClass)

        headerView.compactStyle = preferredCompactHeaderStyle ?? .transparent
        headerView.configure(with: model, sizeClass: sizeClass, environment: environment)

        shortcutView.settings = ShortcutIndicatorView.Settings(
            plainTextModifierFlags: environment.plainTextModifierFlags,
            quickPasteModifierFlags: environment.quickPasteModifierFlags,
            currentModifierFlags: environment.currentModifierFlags
        )
        shortcutView.quickPasteIndex = model.quickPasteIndex
        shortcutView.isEnabled = isEmphasized

        layoutValues = ItemCellLayout(sizeClass: sizeClass, isCompactContentFullSize: isCompactContentFullSize)
        updateTitleEditability()
        needsLayout = true
    }

    override open func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
        cancelPendingWork()
    }

    // MARK: - Density

    public func transition(from source: SizeClass, to destination: SizeClass, progress: Double) {
        sizeClass = destination
        layoutValues = .blend(
            from: ItemCellLayout(sizeClass: source, isCompactContentFullSize: isCompactContentFullSize),
            to: ItemCellLayout(sizeClass: destination, isCompactContentFullSize: isCompactContentFullSize),
            progress: progress
        )
        headerView.transition(from: source, to: destination, progress: progress)
        transitionContent(to: destination, progress: progress)
        needsLayout = true
    }

    // MARK: - Layout

    override open func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        headerView.frame = CGRect(x: 0, y: 0, width: size.width, height: layoutValues.headerHeight)
        bodyView.frame = CGRect(
            x: 0, y: layoutValues.contentTopOffset, width: size.width, height: size.height - layoutValues.contentTopOffset
        )
        shortcutView.place(trailingBottomAt: CGPoint(
            x: size.width - ShortcutIndicatorMetrics.cardInset,
            y: size.height - ShortcutIndicatorMetrics.cardInset
        ))
        layoutContent(in: bodyView.bounds)
    }

    // MARK: - Accessibility

    /// One formatter for every card's label; the header keeps its own for what it draws.
    private static let accessibilityDateFormatter = ItemDateFormatter()

    /// "Text, copied 5 minutes ago from Safari: Dear Ana, …", worked out when VoiceOver asks.
    override open func accessibilityLabel() -> String? {
        guard let model else { return nil }
        let date = model.showsDate
            ? Self.accessibilityDateFormatter.relativeString(for: model.date, now: Date())
            : nil
        return CardAccessibilityLabel().label(for: model, relativeDate: date)
    }

    /// The card is read as a whole: its title, labels and previews are not separate elements.
    override open func accessibilityChildren() -> [Any]? { [] }

    // MARK: - Selection and title editing

    override open func selectionDidChange() {
        super.selectionDidChange()
        shortcutView.isEnabled = isEmphasized
        updateTitleEditability()
    }

    /// Starts renaming the card in place, as a click on the title of a selected card does. Only
    /// a selected card whose title can be edited starts.
    public func beginTitleEditing() {
        headerView.titleLabel.beginEditing()
    }

    /// A click anywhere on the card ends an edit of the title before it does anything else.
    override open func mouseDown(with event: NSEvent) {
        headerView.titleLabel.commitEditing()
        super.mouseDown(with: event)
    }

    override open func rightMouseDown(with event: NSEvent) {
        headerView.titleLabel.commitEditing()
        super.rightMouseDown(with: event)
    }

    /// The title can be edited only on a selected card; losing the selection commits the edit.
    private func updateTitleEditability() {
        headerView.titleLabel.isEditable = isSelected && model?.isTitleEditable == true
    }

    private func commitTitle(_ text: String) {
        guard var model else { return }
        let edit = TitleEdit(typed: text, customTitle: model.customTitle, typeName: model.typeName)
        if case .rename(let newTitle) = edit {
            model.customTitle = newTitle
            self.model = model
        }
        // Show the result at once; the store's update will reconfigure the cell later.
        headerView.setTitle(model.title, placeholder: model.typeName)
        if case .rename(let newTitle) = edit {
            onRename?(newTitle)
        }
    }
}
