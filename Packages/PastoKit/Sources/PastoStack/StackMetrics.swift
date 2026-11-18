import CoreGraphics
import Foundation
import SwiftUI

/// Every number of the Paste Stack: sizes, distances, durations and curves.
nonisolated enum StackMetrics {
    enum Panel {
        static let width: CGFloat = 240
        static let cornerRadius: CGFloat = 26
        /// Transparent space around the panel inside its window, where the shadow falls.
        static let margin: CGFloat = 24
        /// The strip along the bottom edge that resizes the panel.
        static let resizeEdgeHeight: CGFloat = 8

        /// The light line along the inside of the panel's edge.
        static let borderWidth: CGFloat = 0.5
        static let borderWhite: Double = 0.8588
        static let shadowOpacity: Double = 0.2
        static let shadowRadius: CGFloat = 16
        static let shadowOffset: CGFloat = 6
    }

    enum Header {
        static let height: CGFloat = 52
        static let padding: CGFloat = 12
        static let titleSpacing: CGFloat = 8
        static let titleHorizontalPadding: CGFloat = 4
        /// The title's glyph is drawn larger than the room it takes, which its own margins absorb.
        static let titleGlyphFrameSide: CGFloat = 14
        static let titleGlyphSide: CGFloat = 20.5
        static let buttonSpacing: CGFloat = 4
        /// Between the "…" button and the menu that hangs from it.
        static let menuGap: CGFloat = 4
        /// The symbol size of the header buttons.
        static let buttonSymbolSize: CGFloat = 13
    }

    enum List {
        static let horizontalPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 16
        static let cardSpacing: CGFloat = 8
        /// The scroller ends this far above the panel's bottom edge; at the top it starts under
        /// the header.
        static let scrollerBottomInset: CGFloat = 26
        /// Cards fade out as they scroll under the header: from fully visible this far below the
        /// header's bottom edge…
        static let fadeEndBelowHeader: CGFloat = 2
        /// …to invisible this far above it.
        static let fadeStartAboveHeader: CGFloat = 18
        static let emptyStatePadding: CGFloat = 12
        static let emptyStateFontSize: CGFloat = 13
        /// The first-use line above the rows.
        static let firstUseHintFontSize: CGFloat = 11
        /// The room the list opens where something dragged in from elsewhere would be dropped.
        static let dropGap: CGFloat = 48
    }

    enum Card {
        static let width: CGFloat = 208
        static let cornerRadius: CGFloat = 16
        static let shadowOpacity: Double = 0.08
        static let shadowRadius: CGFloat = 2
        static let textPadding: CGFloat = 12
        static let thumbWidth: CGFloat = 40
        static let thumbSymbolSize: CGFloat = 13
        /// The side of an icon inside the thumb.
        static let thumbIconSide: CGFloat = 20
        /// A taller card is cut here, its last lines fading out.
        static let maximumHeight: CGFloat = 208
        /// Where the fade of a cut card starts, as a share of the maximum height.
        static let fadeStart: CGFloat = 0.8

        static let deleteButtonSide: CGFloat = 18
        static let deleteButtonSymbolSize: CGFloat = 9
        /// How far the delete button sticks out of the card's top-right corner.
        static let deleteButtonOverhang: CGFloat = 4
        /// How far into the header's band the delete button of a scrolled card still responds.
        static let deleteButtonReach: CGFloat = 12
        static let deleteButtonPressedScale: CGFloat = 0.85
    }

    /// A row dragged out of its slot.
    enum Drag {
        static let minimumDistance: CGFloat = 3
        /// The card that follows the pointer is drawn with this much room around it, for its
        /// shadow.
        static let imagePadding: CGFloat = 16
        static let liftedOpacity: Double = 0.9
        static let liftedShadowOpacity: Double = 0.25
        static let liftedShadowRadius: CGFloat = 8
        static let liftedShadowOffset: CGFloat = 4
        /// The card gliding back into its slot…
        static let landingDuration: TimeInterval = 0.25
        static let landingCurve = UnitCurve.easeOut
        /// …and fading away once it is there.
        static let landedFadeDuration: TimeInterval = 0.15
    }

    enum Motion {
        /// Rows changing place, the panel changing height, the undo button coming and going.
        static let layout = Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let cardTransition = Animation.spring(response: 0.30, dampingFraction: 1)
        static let deleteButtonPress = Animation.spring(response: 0.2, dampingFraction: 1)
        /// The list scrolling back to show its new first row.
        static let revealFirstRow = Animation.easeInOut(duration: 0.35)

        /// What a card looks like on its way in or out.
        static let transitionScale: CGFloat = 0.94
        static let transitionBlurRadius: CGFloat = 4
        static let transitionOffset: CGFloat = 6
    }

    enum Window {
        /// Where the window's top-left corner goes the first time, before the user has moved it.
        static let initialTopLeft = CGPoint(x: 268, y: 339)
        static let minimumHeightLimit: CGFloat = 160
        /// The share of the screen's visible height the panel may take until the user resizes it.
        static let defaultHeightFraction: CGFloat = 0.7
        /// The point that decides which screen the window is on lies this far below its top edge.
        static let screenAnchorInset: CGFloat = 25
    }

    enum Snap {
        /// Above this speed, in points per second, edges neither catch nor stay caught.
        static let maximumSpeed: CGFloat = 400
        /// An edge only catches on a line it was nearer than this before crossing it.
        static let approachDistance: CGFloat = 30
        static let spanTolerance: CGFloat = 1
        /// The gap left between the panel and a window it rests against.
        static let windowGap: CGFloat = 1
        /// A panel this close to a guide when a drag starts counts as resting on it.
        static let restingTolerance: CGFloat = 0.5
        /// The pull that frees an edge when the pointer heads straight away from the line…
        static let straightPull: CGFloat = 35
        /// …and when it slides along the line.
        static let slidingPull: CGFloat = 140
        /// From this angle to the axis on, a movement counts as sliding along the line.
        static let slidingAngle: CGFloat = .pi / 3
        /// Up to this angle, a movement counts as heading straight across the line.
        static let straightAngle: CGFloat = .pi / 12
        /// How far a freed edge must travel before it can catch again.
        static let rearmDistance: CGFloat = 55
        /// Windows more transparent than this are not guides.
        static let minimumWindowAlpha: Double = 0.2

        static let minimumSampleInterval: TimeInterval = 0.001
        static let staleSampleInterval: TimeInterval = 0.2
        static let newSampleWeight: CGFloat = 0.8
    }
}
