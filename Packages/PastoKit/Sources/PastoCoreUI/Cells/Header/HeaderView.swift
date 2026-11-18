import AppKit
import PastoUI
import UniformTypeIdentifiers

/// The top of a card: a band in the colour of the source application (or of the pinboard), the
/// application's icon overhanging its corner, and the title above the date. In the compact
/// density there is no band and everything sits on one line over the content.
final class HeaderView: CardView {
    private static let labelAxisAnimationKey = "labelAxis"

    let titleLabel = TitleLabel()

    /// How the header looks in the compact density when it floats over the content.
    var compactStyle = HeaderLayout.CompactStyle.transparent

    private let backgroundView = CardView(frame: .zero)
    private let gradientView = GradientEffectView(frame: .zero)
    /// Holds the labels and icons, and clips the overhanging application icon.
    private let contentView = CardView(frame: .zero)
    private let appIconView = NSImageView()
    private let pinboardIconView = NSImageView()
    private let dateLabel = DateLabel()

    private var layoutValues = HeaderLayout(sizeClass: .small, compactStyle: .transparent, isAppIconHidden: false, hasSourceIcon: false)
    private var titleFont: CardFont?
    private var titleColor: CardTextColor?
    private var dateFont: CardFont?
    private var dateColor: CardTextColor?
    /// With Increase Contrast on, white labels over a light band are black at the same opacity.
    /// Without it the header looks as it always does.
    private var usesDarkLabels = false
    private var titleSize = CGSize.zero
    private var dateSize = CGSize.zero
    /// 0 with the title above the date, 1 with both on one line; in between while the labels
    /// move from one arrangement to the other.
    private var inlineProgress: CGFloat = 0
    private var labelAxisAnimator: Animator?

    private var isAppIconHidden = false
    private var hasSourceIcon = false
    private var imageDecoder: ImageDecoder?
    /// The icon last asked for, and the pixel size it was asked at.
    private var iconSource: IconSource?
    private var iconPixelSize = 0
    private let iconRequest = ImageRequest()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        backgroundView.clipsToBounds = true
        contentView.clipsToBounds = true
        gradientView.colors = .pair(top: CardColor.compactHeaderShade, bottom: .clear)
        pinboardIconView.imageScaling = .scaleNone
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        // The card's label names the application and the pinboard; the icons would read as
        // "image", also under the pointer.
        pinboardIconView.setAccessibilityElement(false)
        appIconView.setAccessibilityElement(false)

        addSubview(backgroundView)
        addSubview(gradientView)
        addSubview(contentView)
        contentView.addSubview(pinboardIconView)
        contentView.addSubview(appIconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(dateLabel)

        titleLabel.onEditingChange = { [weak self] in self?.needsLayout = true }
        dateLabel.onTextChange = { [weak self] in self?.dateTextDidChange() }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Content

    func configure(with model: ItemCellModel, sizeClass: SizeClass, environment: ItemCellEnvironment) {
        labelAxisAnimator?.cancel(Self.labelAxisAnimationKey)
        isAppIconHidden = model.pinboardColor != nil
        // An item without a source application shows a generic icon, which counts as one; only
        // an application whose icon cannot be read leaves none.
        hasSourceIcon = model.sourceApplication.map { $0.iconData != nil } ?? true
        imageDecoder = environment.imageDecoder

        backgroundView.fillColor = Self.bandColor(for: model)
        pinboardIconView.isHidden = !isAppIconHidden
        pinboardIconView.image = model.pinboardColor.map {
            PinboardDot.image(color: CardColor.pinboard($0), side: HeaderMetrics.pinboardIconSide)
        }
        appIconView.isHidden = isAppIconHidden
        titleLabel.setText(model.title, placeholder: model.typeName)

        let layout = HeaderLayout(
            sizeClass: sizeClass, compactStyle: compactStyle, isAppIconHidden: isAppIconHidden, hasSourceIcon: hasSourceIcon
        )
        dateLabel.isHidden = !model.showsDate
        dateLabel.clock = environment.now
        dateLabel.isCompact = layout.isDateCompact
        dateLabel.date = model.showsDate ? model.date : nil

        inlineProgress = layout.labelAxis == .horizontal ? 1 : 0
        apply(layout)
        showIcon(IconSource(model.sourceApplication), side: layout.appIconSide)
    }

    /// Changes how the compact header looks after the card was configured, and lays it out
    /// again for `sizeClass`.
    func setCompactStyle(_ style: HeaderLayout.CompactStyle, sizeClass: SizeClass) {
        guard style != compactStyle else { return }
        compactStyle = style
        apply(HeaderLayout(
            sizeClass: sizeClass, compactStyle: style, isAppIconHidden: isAppIconHidden, hasSourceIcon: hasSourceIcon
        ))
    }

    /// Changes the title alone, after a rename.
    func setTitle(_ title: String, placeholder: String) {
        titleLabel.setText(title, placeholder: placeholder)
        titleSize = titleLabel.fittingTextSize
        needsLayout = true
    }

    /// Drops what belongs to the item being shown: the pending icon, the date's timer and any
    /// edit of the title.
    override func prepareForReuse() {
        super.prepareForReuse()
        if iconRequest.isPending { forgetIcon() }
        dateLabel.stopRefreshing()
        titleLabel.cancelEditing()
        labelAxisAnimator?.cancel(Self.labelAxisAnimationKey)
    }

    /// The band takes the pinboard's colour for a pinned item, else the source application's,
    /// else a neutral gray. The text on it is always white.
    private static func bandColor(for model: ItemCellModel) -> NSColor {
        if let pinboardColor = model.pinboardColor { return CardColor.pinboard(pinboardColor) }
        if let color = model.sourceApplication?.color { return NSColor(color) }
        return CardColor.headerDefault
    }

    // MARK: - Density

    /// Blends the header between two densities. Sizes and opacities follow `progress`;
    /// fonts, colours and the date's format switch at once; the labels re-arrange on their own,
    /// slower clock.
    func transition(from source: SizeClass, to destination: SizeClass, progress: Double) {
        let sourceLayout = HeaderLayout(
            sizeClass: source, compactStyle: compactStyle, isAppIconHidden: isAppIconHidden, hasSourceIcon: hasSourceIcon
        )
        let destinationLayout = HeaderLayout(
            sizeClass: destination, compactStyle: compactStyle, isAppIconHidden: isAppIconHidden, hasSourceIcon: hasSourceIcon
        )

        if destinationLayout.labelAxis != layoutValues.labelAxis {
            let animator = labelAxisAnimator ?? Animator(hostView: self)
            labelAxisAnimator = animator
            animator.animate(
                key: Self.labelAxisAnimationKey,
                from: inlineProgress,
                to: destinationLayout.labelAxis == .horizontal ? 1 : 0,
                duration: HeaderMetrics.labelAxisDuration,
                timing: .easeOut,
                update: { [weak self] value in
                    self?.inlineProgress = value
                    self?.needsLayout = true
                }
            )
        }

        apply(.blend(from: sourceLayout, to: destinationLayout, progress: progress))

        // Past the half-way point the icon is redrawn at the size the destination asks for.
        if progress > 0.5, let iconSource {
            showIcon(iconSource, side: destinationLayout.appIconSide)
        }
    }

    private func apply(_ layout: HeaderLayout) {
        layoutValues = layout
        backgroundView.alphaValue = layout.bandAlpha
        gradientView.alphaValue = layout.gradientAlpha
        appIconView.alphaValue = layout.appIconAlpha

        let darkLabels = prefersDarkLabels
        let contrastChanged = darkLabels != usesDarkLabels
        usesDarkLabels = darkLabels
        if titleFont != layout.titleFont || titleColor != layout.titleColor || contrastChanged {
            titleFont = layout.titleFont
            titleColor = layout.titleColor
            titleLabel.setFont(layout.titleFont, color: labelColor(layout.titleColor))
        }
        if dateFont != layout.dateFont {
            dateFont = layout.dateFont
            dateLabel.font = layout.dateFont.font
        }
        if dateColor != layout.dateColor || contrastChanged {
            dateColor = layout.dateColor
            dateLabel.textColor = labelColor(layout.dateColor)
        }
        dateLabel.isCompact = layout.isDateCompact

        titleSize = titleLabel.fittingTextSize
        dateSize = dateLabel.intrinsicContentSize
        needsLayout = true
    }

    private func dateTextDidChange() {
        dateSize = dateLabel.intrinsicContentSize
        needsLayout = true
    }

    // MARK: - Increase Contrast

    /// Whether the labels are to be dark: Increase Contrast is on and they sit on a light band.
    private var prefersDarkLabels: Bool {
        guard layoutValues.labelsOnBand, NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
              let band = backgroundView.fillColor
        else { return false }
        // The band's colour as it shows in this appearance.
        var components: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            components = band.usingColorSpace(.sRGB)
        }
        guard let components else { return false }
        return HeaderLayout.prefersDarkLabels(
            onBandRed: components.redComponent, green: components.greenComponent, blue: components.blueComponent
        )
    }

    private func labelColor(_ color: CardTextColor) -> NSColor {
        if usesDarkLabels, case .white(let alpha) = color {
            return NSColor.black.withAlphaComponent(alpha)
        }
        return color.color
    }

    /// The band's colour may resolve differently, or the setting may have changed.
    private func updateLabelContrast() {
        guard prefersDarkLabels != usesDarkLabels else { return }
        apply(layoutValues)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLabelContrast()
    }

    /// Whatever thread the notification comes on, the labels change on the main one.
    @objc private nonisolated func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
        Task { @MainActor in updateLabelContrast() }
    }

    // MARK: - Icon

    /// What the icon at the header's corner shows.
    private enum IconSource: Equatable {
        /// The item has no source application: the system's generic application icon, in
        /// colour and untinted.
        case generic
        /// The source application's icon could not be read: no icon at all.
        case missing
        case data(Data)

        init(_ application: ItemCellModel.SourceApplication?) {
            guard let application else {
                self = .generic
                return
            }
            self = application.iconData.map(IconSource.data) ?? .missing
        }
    }

    private static let genericApplicationIcon = NSWorkspace.shared.icon(for: .application)

    /// Shows the icon `source` stands for, decoded for an icon view `side` points wide. A small
    /// icon is decoded on the spot, so the card has it from its first frame.
    private func showIcon(_ source: IconSource, side: CGFloat) {
        guard !isAppIconHidden else {
            forgetIcon()
            return
        }
        let pixelSize = Int((side * (window?.backingScaleFactor ?? 2)).rounded(.up))
        guard source != iconSource || pixelSize != iconPixelSize else { return }

        // The same icon at another size (a density change) stays up until the new bitmap is in.
        let isSameIcon = source == iconSource && iconPixelSize != 0
        iconSource = source
        iconPixelSize = pixelSize

        switch source {
        case .generic:
            iconRequest.cancel()
            appIconView.image = Self.genericApplicationIcon
        case .missing:
            iconRequest.cancel()
            appIconView.image = nil
        case .data(let data):
            guard let imageDecoder else {
                appIconView.image = nil
                return
            }
            let size = CGSize(width: side, height: side)
            let iconView = appIconView
            iconRequest.load(data, maxPixelSize: pixelSize, with: imageDecoder) { state in
                switch state {
                case .loading:
                    if !isSameIcon { iconView.image = nil }
                case .loaded(let image):
                    iconView.image = NSImage(cgImage: image, size: size)
                case .failed:
                    iconView.image = nil
                }
            }
        }
    }

    private func forgetIcon() {
        iconRequest.cancel()
        iconSource = nil
        iconPixelSize = 0
        appIconView.image = nil
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let layout = layoutValues
        backgroundView.frame = bounds
        contentView.frame = bounds
        gradientView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: HeaderMetrics.gradientHeight)

        let iconSide = layout.appIconSide
        appIconView.frame = CGRect(
            x: bounds.width + layout.appIconOffset - iconSide,
            y: (bounds.height - iconSide) / 2,
            width: iconSide,
            height: iconSide
        )

        let dotSide = HeaderMetrics.pinboardIconSide
        pinboardIconView.frame = CGRect(
            x: bounds.width + layout.pinboardIconOffset - dotSide,
            y: (bounds.height - dotSide) / 2,
            width: dotSide,
            height: dotSide
        )

        layoutLabels(trailingOffset: layout.labelsTrailingOffset)
    }

    /// Title and date start at the leading inset, are centred vertically as a block and never
    /// reach past the trailing offset. Stacked, the date sits under the title; inline, right
    /// after it. `inlineProgress` blends the two arrangements.
    private func layoutLabels(trailingOffset: CGFloat) {
        let leading = HeaderMetrics.sideInset
        let available = max(bounds.width + trailingOffset - leading, 0)
        let showsDate = !dateLabel.isHidden
        let dateWidth = showsDate ? min(dateSize.width, available) : 0

        let stackedSpacing = HeaderMetrics.stackedLabelSpacing
        let stackedHeight = titleSize.height + (showsDate ? stackedSpacing + dateSize.height : 0)
        let stackedTop = (bounds.height - stackedHeight) / 2
        let stackedTitle = CGRect(
            x: leading, y: stackedTop, width: titleWidth(in: available), height: titleSize.height
        )
        let stackedDate = CGRect(
            x: leading, y: stackedTop + titleSize.height + stackedSpacing, width: dateWidth, height: dateSize.height
        )

        // Inline, the date keeps its width and the title gives way.
        let inlineTitleWidth = titleWidth(in: available - dateWidth - HeaderMetrics.inlineLabelSpacing)
        let inlineTitle = CGRect(
            x: leading, y: (bounds.height - titleSize.height) / 2, width: inlineTitleWidth, height: titleSize.height
        )
        let inlineDate = CGRect(
            x: leading + inlineTitleWidth + HeaderMetrics.inlineLabelSpacing,
            y: (bounds.height - dateSize.height) / 2,
            width: dateWidth,
            height: dateSize.height
        )

        titleLabel.frame = .interpolate(from: stackedTitle, to: inlineTitle, progress: inlineProgress)
        dateLabel.setAlignmentRect(.interpolate(from: stackedDate, to: inlineDate, progress: inlineProgress))
    }

    /// The title is as wide as its text, up to the room there is; while it is being edited it
    /// takes all the room.
    private func titleWidth(in room: CGFloat) -> CGFloat {
        max(titleLabel.isEditing ? room : min(titleSize.width, room), 0)
    }
}
