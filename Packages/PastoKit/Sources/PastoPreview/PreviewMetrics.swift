import AppKit

/// Every number of the preview, the editors and the New Text Item window.
nonisolated enum PreviewMetrics {
    // MARK: Preview view

    static let headerHeight: CGFloat = 38
    static let contentSideMargin: CGFloat = 5
    /// What the header, the footer and the side margins add to the size of the content.
    static let chromeSize = CGSize(width: 10, height: 76)
    static let minimumContentSize = CGSize(width: 380, height: 240)
    static let contentCornerRadius: CGFloat = 5
    static let contentBorderWidth: CGFloat = 0.5
    static let contentBorderOpacity: CGFloat = 0.1
    /// Gap under the content while editing, when the footer is hidden.
    static let editingBottomMargin: CGFloat = 5

    /// Fraction of the main screen a content view without a size of its own gets.
    static let defaultScreenFraction: CGFloat = 0.25
    /// Fraction of the main screen that bounds the content views that do have one.
    static let largeScreenFraction: CGFloat = 0.5

    // MARK: Headers

    static let closeButtonLeading: CGFloat = 10
    static let closeButtonOpacity: CGFloat = 0.6
    static let titleLeading: CGFloat = 8
    static let titleOpacity: CGFloat = 0.8
    static let actionSpacing: CGFloat = 8
    static let headerTrailing: CGFloat = 8
    static let editorHeaderMargin: CGFloat = 8
    /// The pinboard menu opens this far below the Pin button's origin.
    static let pinMenuOffset: CGFloat = 10

    // MARK: Buttons

    /// A button with a title; one with only a symbol is smaller and tighter.
    static let titledButtonHeight: CGFloat = 24
    static let symbolButtonHeight: CGFloat = 22
    static let titledButtonPadding: CGFloat = 12
    static let symbolButtonPadding: CGFloat = 8
    static let buttonMinimumWidth: CGFloat = 32
    static let buttonContentSpacing: CGFloat = 4
    static let buttonSymbolPointSize: CGFloat = 13
    /// Opacity of the black (light) or white (dark) fill. A button with a title is filled at
    /// rest; one with only a symbol only under the pointer.
    static let titledButtonRestFillOpacity: CGFloat = 0.05
    static let titledButtonHoverFillOpacity: CGFloat = 0.10
    static let symbolButtonHoverFillOpacity: CGFloat = 0.05
    static let buttonPressedFillOpacity: CGFloat = 0.15
    static let buttonSelectedFillOpacity: CGFloat = 0.10

    // MARK: Footer

    static let footerInsets = NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
    static let footerSeparator = "  ·  "

    // MARK: Text

    static let editorFontName = "HelveticaNeue"
    static let editorFontSize: CGFloat = 13
    static let editorInset = CGSize(width: 8, height: 10)
    /// Only this many UTF-16 units of a text are measured to size its preview.
    static let textMeasureLimit = 2000
    /// The box a text is measured in when there is no screen.
    static let textFallbackBox = CGSize(width: 1000, height: 1000)
    static let textExtraWidth: CGFloat = 20
    /// Text with no colour but a background of its own is drawn black when that background, laid
    /// over the preview's, is lighter than this (Rec. 601 luma, 0...1), and white otherwise.
    static let textOnBackgroundLightnessThreshold: CGFloat = 0.55
    static let statisticsSpacing: CGFloat = 8
    /// The dot between two counts, in black (light) or white (dark) at this opacity.
    static let statisticsSeparator = "\u{B7}"
    static let statisticsSeparatorOpacity: CGFloat = 0.26
    /// How long Writing Tools waits for the editor to take focus.
    static let writingToolsDelay = Duration.milliseconds(500)

    // MARK: Link

    static let loaderSide: CGFloat = 24
    static let pageTimeout: TimeInterval = 60
    static let linkEditorInset = CGSize(width: 12, height: 12)

    // MARK: Image

    /// An image can be magnified up to this many times its real size.
    static let maximumImageScale: CGFloat = 2
    /// Compression of the JPEG an edited image is saved as when it cannot be a PNG.
    static let jpegFallbackQuality = 0.5

    // MARK: Colour

    static let colorCodeFontSize: CGFloat = 22
    static let colorPanelGap: CGFloat = 20
    static let colorFormatSpacing: CGFloat = 4
    static let colorFormatsSpacing: CGFloat = 8
    /// The RGB components are scaled by 256, not 255, so a full channel reads 256.
    static let rgbComponentScale = 256.0

    // MARK: Files

    static let filesIconSide: CGFloat = 160

    // MARK: Unknown

    static let unavailableSpacing: CGFloat = 16
    static let unavailableTextSpacing: CGFloat = 4
    static let unavailableSideMargin: CGFloat = 48
    static let unavailableSymbolSide: CGFloat = 60

    // MARK: Windows

    static let cascadeStep: CGFloat = 30
    /// After ⌘C in the strip, the popover closes this much later.
    static let closeAfterCopyDelay = Duration.milliseconds(100)
    static let newItemMinimumSize = CGSize(width: 500, height: 360)
    static let newItemFooterSideMargin: CGFloat = 12
    static let newItemFooterBottomMargin: CGFloat = 11
}
