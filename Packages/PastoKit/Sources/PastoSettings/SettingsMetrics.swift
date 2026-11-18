import AppKit

/// Every layout number of the Settings window.
enum SettingsMetrics {
    // MARK: Window

    /// The window is born with this content rect; its real size comes from its content.
    static let initialContentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
    static let sidebarWidth: CGFloat = 200
    static let contentWidth: CGFloat = 440
    /// The window's height, the same on every pane. It is fixed rather than taken from the
    /// General pane, so that the window measures 640 × 550 whatever that pane comes to.
    static let windowHeight: CGFloat = 550
    static let headerHeight: CGFloat = 52
    static let headerTitleInset: CGFloat = 30

    // MARK: Sidebar

    static let sidebarRowHeight: CGFloat = 32
    static let sidebarIconPointSize: CGFloat = 14
    static let sidebarBadgePointSize: CGFloat = 16
    /// Around the list, at the top only: negative on macOS 26 and later (0 before), which puts the
    /// first row 52.5 pt below the window's top edge.
    static let sidebarListTopPadding: CGFloat = -14

    // MARK: Panes

    /// On both sides and at the bottom of a pane; the header already stands above it.
    static let paneHorizontalInset: CGFloat = 20
    static let paneBottomInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    /// Between Privacy's two boxes of switches, which go together.
    static let switchBoxSpacing: CGFloat = 16

    // MARK: Section box

    static let boxSpacing: CGFloat = 10
    static let boxPadding: CGFloat = 10
    static let boxCornerRadius: CGFloat = 12
    /// Of the label colour, as the fill of a box.
    static let boxFillOpacity = 0.03
    /// The title over a box lines up with the box's content.
    static let sectionTitleInset: CGFloat = 10
    /// Between a box's title and the box.
    static let sectionTitleSpacing: CGFloat = 6

    // MARK: Rows

    static let rowSubtitleSpacing: CGFloat = 2
    /// A row's control may be no taller than this.
    static let rowControlMaxHeight: CGFloat = 16

    // MARK: Paste Items

    static let illustrationSize = CGSize(width: 96, height: 64)
    static let illustrationCornerRadius: CGFloat = 8
    /// The illustration: an SF Symbol on a tinted ground.
    static let illustrationSymbolPointSize: CGFloat = 28
    static let illustrationBackdropOpacity = 0.12

    // MARK: Warning pills (General's Accessibility, Intelligence's requirements)

    static let warningPillTopSpacing: CGFloat = 6
    static let warningPillPadding: CGFloat = 6
    static let warningPillCornerRadius: CGFloat = 5
    /// Of black (light) or white (dark), as the fill and as the chevron.
    static let warningPillFillOpacity: CGFloat = 0.05
    static let warningPillChevronOpacity: CGFloat = 0.26

    // MARK: Keep History

    static let sliderBlockSpacing: CGFloat = 6

    // MARK: Ignored applications

    static let applicationRowHeight: CGFloat = 40
    static let emptyApplicationListMinHeight: CGFloat = 40
    static let listButtonSize: CGFloat = 24
    static let applicationIconSize: CGFloat = 24

    // MARK: Shortcuts

    static let modifierChevronPointSize: CGFloat = 9
    static let modifierChevronBoxSide: CGFloat = 16
    static let modifierChevronCornerRadius: CGFloat = 4
    /// Between a modifier's name and its chevron.
    static let modifierLabelSpacing: CGFloat = 6
}
