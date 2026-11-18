import CoreGraphics
import Foundation

// Pasto's app icon: three clipboard cards fanned out and rising from a meadow ("pasto" is Spanish
// for grass), on a green tile.
//
// Everything is described on Apple's 1024-unit macOS icon grid: an 824-unit tile with continuous
// corners, centred, leaving a 100-unit margin for the drop shadow. Smaller renditions get their own
// simplified art (`IconArt.medium`, `.small`, `.tiny`) whose key edges land on whole pixels.

enum Grid {
    static let canvas: CGFloat = 1024
    static let tileSide: CGFloat = 824
    static let tileCornerRadius: CGFloat = 185.4
    static let centerX: CGFloat = canvas / 2
    static var tileInset: CGFloat { (canvas - tileSide) / 2 }
    static var tileRect: CGRect { CGRect(x: tileInset, y: tileInset, width: tileSide, height: tileSide) }
}

/// Every colour of the icon. The values are documented in docs/design/icon.md; keep them in sync.
enum Palette {
    // Tile: a fresh, slightly yellow green at the top that deepens into a blue-leaning emerald.
    static let tileTop = RGBA(0x7DD46A)
    static let tileMiddle = RGBA(0x2BA65B)
    static let tileBottom = RGBA(0x0A6B4A)
    static let tileGlow = RGBA(0xFFF7D6, alpha: 0.24)
    static let tileRim = RGBA(0xFFFFFF, alpha: 0.50)

    // Cards.
    static let cardFrontTop = RGBA(0xFFFFFF)
    static let cardFrontBottom = RGBA(0xF0F7F2)
    static let cardBackTop = RGBA(0xE8F6EB)
    static let cardBackBottom = RGBA(0xD6EEDC)
    /// Where the cards sink into the grass they take on its shade.
    static let cardFrontShade = RGBA(0x7DB590)
    static let cardBackShade = RGBA(0x5E9F75)
    static let cardTitleLine = RGBA(0xA9D3B4)
    /// Small renditions need more contrast to keep a one-pixel line visible.
    static let cardTitleLineSmall = RGBA(0x7DBB8F)
    static let cardBackSmall = RGBA(0xA7D8B4)
    static let cardTextLine = RGBA(0xDCEDE1)
    static let cardShadow = RGBA(0x04381F, alpha: 0.30)

    // Grass, far to near: sunlit blades behind the cards, a middle row in front of them, and a dark
    // front row that grounds the picture. Each row darkens towards its roots.
    static let grassFarTip = RGBA(0x9BDB6A)
    static let grassFarRoot = RGBA(0x3DAF5C)
    static let grassFarFoldTip = RGBA(0xBCE985)
    static let grassFarFoldRoot = RGBA(0x5BC066)
    static let grassMidTip = RGBA(0x45B45B)
    static let grassMidRoot = RGBA(0x137645)
    static let grassMidFoldTip = RGBA(0x66CA68)
    static let grassMidFoldRoot = RGBA(0x1E8A4E)
    static let grassNearTip = RGBA(0x1C8A4B)
    static let grassNearRoot = RGBA(0x08532F)
    static let grassNearFoldTip = RGBA(0x2A9C54)
    static let grassNearFoldRoot = RGBA(0x0D6139)
    static let grassShadow = RGBA(0x033019, alpha: 0.28)

    static let tileShadow = RGBA(0x000000, alpha: 0.30)

    // Dark appearance (Icon Composer): the tile turns into a night meadow, the cards stay white.
    static let darkTileTop = RGBA(0x1D4A31)
    static let darkTileBottom = RGBA(0x0A2116)
}

// MARK: - Art description

struct CardArt {
    var frame: CGRect
    var radius: CGFloat
    /// Degrees, clockwise, around `pivot`.
    var rotation: CGFloat = 0
    var pivot = CGPoint(x: Grid.centerX, y: 980)
    var top: RGBA
    var bottom: RGBA
    /// The card darkens into this colour where it sinks into the grass, between `shadeFrom` and
    /// `shadeTo` (design units, measured on the unrotated card). Nil keeps it flat.
    var shade: RGBA?
    var shadeFrom: CGFloat = 640
    var shadeTo: CGFloat = 860

    var transform: CGAffineTransform { rotationTransform(rotation, around: pivot) }
    var path: CGPath { continuousRoundedRect(frame, radius: radius).transformed(transform) }
    var paint: Paint {
        var stops = [GradientStop(0, top)]
        let span = shadeTo - frame.minY
        if let shade {
            stops.append(GradientStop((shadeFrom - frame.minY) / span, bottom))
            stops.append(GradientStop(1, shade))
        } else {
            stops.append(GradientStop(1, bottom))
        }
        return Paint.linear(from: CGPoint(x: 0, y: frame.minY), to: CGPoint(x: 0, y: shadeTo), stops: stops)
            .transformed(transform)
    }
}

struct TextLine {
    var rect: CGRect
    var color: RGBA
}

struct GrassRow {
    var name: String
    var baseY: CGFloat
    var blades: [Blade]
    var tip: RGBA
    var root: RGBA
    /// The gradient runs from `root` at `baseY` to `tip` at this height.
    var tipY: CGFloat
    /// Lighter colours for the half of each blade that faces the light (the outside of its bend).
    /// Nil draws flat blades, which is what the small renditions want.
    var fold: (tip: RGBA, root: RGBA)?

    var paint: Paint { .vertical(tip, root, from: tipY, to: baseY) }

    /// One item per blade and its lit half, back to front. The roots sit below the tile, so the rows
    /// need no ground band: whatever shows between blades is grass from the row behind.
    var items: [Item] {
        var items: [Item] = []
        for blade in blades {
            let outline = BladeOutline(blade, baseY: baseY)
            items.append(Item(path: outline.path, paint: paint))
            if let fold {
                items.append(Item(path: outline.half(left: blade.lean >= 0),
                                  paint: .vertical(fold.tip, fold.root, from: tipY, to: baseY)))
            }
        }
        return items
    }
}

/// Optional finishing touches; the small renditions drop the ones that would only add noise.
struct Effects {
    var tileGlow = true
    var tileRim = true
    var cardShadows = true
    /// Bright inner edge along the top of the back cards.
    var cardEdgeLight = true
    /// Soft shadow the middle grass row casts on the cards.
    var grassShadow = true
}

struct IconArt {
    var tileInset: CGFloat
    var tileTop = Palette.tileTop
    var tileMiddle = Palette.tileMiddle
    var tileBottom = Palette.tileBottom
    var backCards: [CardArt]
    var frontCard: CardArt
    var textLines: [TextLine]
    var grassBehind: GrassRow?
    var grassMiddle: GrassRow
    var grassFront: GrassRow?
    var effects = Effects()

    var tileRect: CGRect {
        CGRect(x: tileInset, y: tileInset, width: Grid.canvas - 2 * tileInset, height: Grid.canvas - 2 * tileInset)
    }

    var tilePath: CGPath {
        continuousRoundedRect(tileRect, radius: Grid.tileCornerRadius * tileRect.width / Grid.tileSide)
    }

    /// The art to use for a rendition of `pixels` × `pixels`.
    static func forPixelSize(_ pixels: Int) -> IconArt {
        switch pixels {
        case ..<24: return tiny
        case ..<48: return small
        case ..<96: return medium
        default: return full
        }
    }
}

// MARK: - Renditions

extension IconArt {
    /// 128 px and up, the Icon Composer layers and the exports.
    static let full: IconArt = {
        let width: CGFloat = 380
        let front = CardArt(
            frame: CGRect(x: Grid.centerX - width / 2, y: 226, width: width, height: 690),
            radius: 48, top: Palette.cardFrontTop, bottom: Palette.cardFrontBottom, shade: Palette.cardFrontShade)
        // The back cards start lower than the front one: the fan lifts their inner corner, and it must
        // stay hidden behind the front card instead of poking out above it.
        let backFrame = CGRect(x: Grid.centerX - width / 2, y: 274, width: width, height: 650)
        let backLeft = CardArt(frame: backFrame, radius: 48, rotation: -12,
                               top: Palette.cardBackTop, bottom: Palette.cardBackBottom, shade: Palette.cardBackShade,
                               shadeFrom: 600, shadeTo: 820)
        var backRight = backLeft
        backRight.rotation = 12

        let lineX = front.frame.minX + 52
        let lineWidth = width - 104
        return IconArt(
            tileInset: Grid.tileInset,
            backCards: [backLeft, backRight],
            frontCard: front,
            textLines: [
                TextLine(rect: CGRect(x: lineX, y: 290, width: lineWidth * 0.6, height: 26), color: Palette.cardTitleLine),
                TextLine(rect: CGRect(x: lineX, y: 344, width: lineWidth, height: 20), color: Palette.cardTextLine),
                TextLine(rect: CGRect(x: lineX, y: 384, width: lineWidth * 0.86, height: 20), color: Palette.cardTextLine),
                TextLine(rect: CGRect(x: lineX, y: 424, width: lineWidth * 0.94, height: 20), color: Palette.cardTextLine),
                TextLine(rect: CGRect(x: lineX, y: 464, width: lineWidth * 0.68, height: 20), color: Palette.cardTextLine),
            ],
            grassBehind: GrassRow(
                name: "grass-far", baseY: 1000,
                blades: [
                    // Two tall tufts flanking the fan, leaning outwards.
                    Blade(150, width: 92, height: 500, lean: -120, stiffness: 0.4),
                    Blade(190, width: 100, height: 548, lean: -62, stiffness: 0.45),
                    Blade(232, width: 90, height: 480, lean: 50),
                    Blade(792, width: 90, height: 480, lean: -50),
                    Blade(834, width: 100, height: 548, lean: 62, stiffness: 0.45),
                    Blade(874, width: 92, height: 500, lean: 120, stiffness: 0.4),
                ],
                tip: Palette.grassFarTip, root: Palette.grassFarRoot, tipY: 440,
                fold: (Palette.grassFarFoldTip, Palette.grassFarFoldRoot)),
            grassMiddle: GrassRow(
                name: "grass-middle", baseY: 1010,
                blades: [
                    // A light breeze to the right: blades layer like scales instead of crossing.
                    // The first one leans out to frame the left edge.
                    Blade(96, width: 90, height: 420, lean: -70, stiffness: 0.45),
                    Blade(160, width: 92, height: 380, lean: 40),
                    Blade(222, width: 88, height: 440, lean: 70),
                    Blade(286, width: 92, height: 360, lean: 20),
                    Blade(346, width: 88, height: 410, lean: 64),
                    Blade(408, width: 92, height: 350, lean: -24),
                    Blade(470, width: 90, height: 420, lean: 50, stiffness: 0.55),
                    Blade(532, width: 92, height: 370, lean: 14),
                    Blade(594, width: 88, height: 430, lean: 70),
                    Blade(656, width: 92, height: 356, lean: -20),
                    Blade(718, width: 88, height: 412, lean: 56),
                    Blade(780, width: 92, height: 370, lean: 26),
                    Blade(842, width: 90, height: 430, lean: 80, stiffness: 0.45),
                    Blade(910, width: 92, height: 400, lean: 96, stiffness: 0.42),
                ],
                tip: Palette.grassMidTip, root: Palette.grassMidRoot, tipY: 580,
                fold: (Palette.grassMidFoldTip, Palette.grassMidFoldRoot)),
            grassFront: GrassRow(
                name: "grass-near", baseY: 1016,
                blades: [
                    Blade(90, width: 120, height: 300, lean: 40),
                    Blade(172, width: 116, height: 270, lean: -30),
                    Blade(256, width: 120, height: 320, lean: 60),
                    Blade(340, width: 116, height: 280, lean: 20),
                    Blade(424, width: 120, height: 310, lean: 50),
                    Blade(508, width: 116, height: 270, lean: -26),
                    Blade(592, width: 120, height: 320, lean: 56),
                    Blade(676, width: 116, height: 280, lean: 24),
                    Blade(760, width: 120, height: 310, lean: 60),
                    Blade(844, width: 116, height: 270, lean: -20),
                    Blade(930, width: 120, height: 300, lean: 50),
                ],
                tip: Palette.grassNearTip, root: Palette.grassNearRoot, tipY: 720,
                fold: (Palette.grassNearFoldTip, Palette.grassNearFoldRoot)))
    }()

    /// 64 px (one pixel is 16 units): the same picture with two thicker text lines on whole pixels
    /// and fewer, wider blades.
    static let medium: IconArt = {
        var art = full
        let width: CGFloat = 384
        art.frontCard.frame = CGRect(x: Grid.centerX - width / 2, y: 240, width: width, height: 680)
        art.backCards = art.backCards.map {
            var card = $0
            card.frame = CGRect(x: Grid.centerX - width / 2, y: 288, width: width, height: 640)
            return card
        }
        art.textLines = [
            TextLine(rect: CGRect(x: 384, y: 304, width: 160, height: 32), color: Palette.cardTitleLine),
            TextLine(rect: CGRect(x: 384, y: 368, width: 256, height: 32), color: Palette.cardTextLine),
        ]
        art.grassBehind?.blades = [
            Blade(176, width: 128, height: 500, lean: -60, stiffness: 0.45),
            Blade(848, width: 128, height: 500, lean: 60, stiffness: 0.45),
        ]
        // The same breeze as the full art, with half as many blades.
        art.grassMiddle.blades = [
            Blade(112, width: 136, height: 400, lean: -60, stiffness: 0.45),
            Blade(240, width: 136, height: 380, lean: 56),
            Blade(368, width: 136, height: 400, lean: 48),
            Blade(496, width: 136, height: 350, lean: 12),
            Blade(624, width: 136, height: 410, lean: 60),
            Blade(752, width: 136, height: 370, lean: 30),
            Blade(896, width: 136, height: 410, lean: 90, stiffness: 0.42),
        ]
        art.grassFront?.blades = [
            Blade(128, width: 168, height: 290, lean: 40),
            Blade(304, width: 168, height: 300, lean: 50),
            Blade(480, width: 168, height: 280, lean: 20),
            Blade(656, width: 168, height: 300, lean: 50),
            Blade(832, width: 168, height: 290, lean: 40),
        ]
        art.effects.cardEdgeLight = false
        return art
    }()

    /// 32 px (one pixel is 32 units): a 26 px tile like the system's, the front card on whole pixels
    /// and clearly the brightest shape, the back cards reduced to tinted slivers, and a handful of
    /// broad, flat blades.
    static let small: IconArt = {
        let front = CardArt(frame: CGRect(x: 352, y: 224, width: 320, height: 700), radius: 64,
                            top: Palette.cardFrontTop, bottom: Palette.cardFrontTop, shade: Palette.cardFrontShade,
                            shadeFrom: 560, shadeTo: 800)
        let backFrame = CGRect(x: 352, y: 288, width: 320, height: 640)
        let backLeft = CardArt(frame: backFrame, radius: 64, rotation: -14, top: Palette.cardBackSmall,
                               bottom: Palette.cardBackSmall, shade: Palette.cardBackShade, shadeFrom: 520, shadeTo: 760)
        var backRight = backLeft
        backRight.rotation = 14
        var art = IconArt(
            tileInset: 96,
            backCards: [backLeft, backRight],
            frontCard: front,
            textLines: [
                TextLine(rect: CGRect(x: 416, y: 288, width: 160, height: 32), color: Palette.cardTitleLineSmall),
                TextLine(rect: CGRect(x: 416, y: 352, width: 192, height: 32), color: Palette.cardTitleLine),
            ],
            grassBehind: GrassRow(
                name: "grass-far", baseY: 1000,
                blades: [
                    Blade(176, width: 192, height: 560, lean: -90, stiffness: 0.45),
                    Blade(848, width: 192, height: 560, lean: 90, stiffness: 0.45),
                ],
                tip: Palette.grassFarTip, root: Palette.grassFarRoot, tipY: 440),
            grassMiddle: GrassRow(
                name: "grass-middle", baseY: 1000,
                blades: [
                    Blade(176, width: 200, height: 440, lean: -40),
                    Blade(344, width: 200, height: 400, lean: 44),
                    Blade(512, width: 200, height: 440, lean: 36),
                    Blade(680, width: 200, height: 400, lean: 52),
                    Blade(848, width: 200, height: 440, lean: 64),
                ],
                // Darker than at full size: light tips would melt into the tile at this scale.
                tip: Palette.grassNearTip, root: Palette.grassMidRoot, tipY: 560),
            grassFront: GrassRow(
                name: "grass-near", baseY: 1000,
                blades: [
                    Blade(256, width: 256, height: 290, lean: 30),
                    Blade(512, width: 256, height: 300, lean: 40),
                    Blade(768, width: 256, height: 290, lean: 30),
                ],
                tip: Palette.grassNearTip, root: Palette.grassNearRoot, tipY: 720))
        art.effects = Effects(tileGlow: true, tileRim: false, cardShadows: true, cardEdgeLight: false, grassShadow: false)
        return art
    }()

    /// 16 px (one pixel is 64 units): a 12 px tile like the system's own small icons, one white card
    /// on whole pixels and three dark blades over its lower half. At this size it only has to read as
    /// "white card in the grass".
    static let tiny: IconArt = {
        let front = CardArt(frame: CGRect(x: 320, y: 256, width: 384, height: 640), radius: 64,
                            top: Palette.cardFrontTop, bottom: Palette.cardFrontTop, shade: Palette.cardFrontShade,
                            shadeFrom: 576, shadeTo: 768)
        var art = IconArt(
            tileInset: 128,
            backCards: [],
            frontCard: front,
            textLines: [TextLine(rect: CGRect(x: 384, y: 384, width: 192, height: 64), color: Palette.cardTitleLineSmall)],
            grassBehind: nil,
            grassMiddle: GrassRow(
                name: "grass-near", baseY: 1000,
                blades: [
                    Blade(256, width: 320, height: 448, lean: -24),
                    Blade(512, width: 320, height: 384, lean: 24),
                    Blade(768, width: 320, height: 448, lean: 40),
                ],
                tip: Palette.grassNearTip, root: Palette.grassNearRoot, tipY: 576),
            grassFront: nil)
        art.effects = Effects(tileGlow: false, tileRim: false, cardShadows: false, cardEdgeLight: false, grassShadow: false)
        return art
    }()
}

// MARK: - Scenes

extension IconArt {
    enum TileShape {
        /// The macOS icon: continuous-corner tile with its drop shadow, on the 1024 grid.
        case classic
        /// The same tile without the shadow, for exports cropped to the tile (favicons).
        case flat
        /// A plain square, for platforms that apply their own mask (apple-touch-icon).
        case square
    }

    /// The classic macOS icon: tile with its drop shadow, everything else clipped to the tile.
    func classicScene(shape: TileShape = .classic) -> Scene {
        let rect = tileRect
        let tile = shape == .square ? CGPath(rect: rect, transform: nil) : tilePath
        var layers: [Layer] = []

        layers.append(Layer(name: "tile", items: [
            Item(path: tile, paint: tileGradient),
        ], shadow: shape == .classic ? Shadow(dy: 10, blur: 20, color: Palette.tileShadow) : nil))

        var lighting: [Item] = []
        if effects.tileGlow {
            // Soft light falling from above; it lifts the top half without adding a visible shape.
            lighting.append(Item(path: tile, paint: .radial(
                center: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.12), radius: rect.height * 0.8,
                stops: [GradientStop(0, Palette.tileGlow), GradientStop(1, Palette.tileGlow.opacity(0))])))
        }
        layers.append(Layer(name: "tile-light", items: lighting))

        layers.append(contentsOf: contentLayers(withShadows: true).map {
            var layer = $0
            layer.clip = tile
            return layer
        })

        if effects.tileRim {
            // A thin bright rim along the top edge that fades out down the sides. Stroked at twice the
            // visible width because the outer half falls outside the clip.
            layers.append(Layer(name: "tile-rim", items: [
                Item(path: tile, paint: .linear(
                    from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.minY + rect.height * 0.42),
                    stops: [GradientStop(0, Palette.tileRim), GradientStop(1, Palette.tileRim.opacity(0))]),
                     strokeWidth: 6, clip: tile),
            ]))
        }
        return Scene(side: Grid.canvas, layers: layers)
    }

    var tileGradient: Paint {
        let rect = tileRect
        // Slightly diagonal, from the top-left: the light comes from above, a touch to the left.
        return .linear(
            from: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY),
            to: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.maxY),
            stops: [GradientStop(0, tileTop), GradientStop(0.52, tileMiddle), GradientStop(1, tileBottom)])
    }

    /// Cards and grass, back to front. Without shadows these are exactly the Icon Composer layers.
    func contentLayers(withShadows: Bool) -> [Layer] {
        var layers: [Layer] = []
        let cardShadow = withShadows && effects.cardShadows ? Shadow(dy: 12, blur: 36, color: Palette.cardShadow) : nil

        if let row = grassBehind {
            layers.append(Layer(name: row.name, items: row.items))
        }

        var backItems: [Item] = []
        for card in backCards {
            backItems.append(Item(path: card.path, paint: card.paint))
            if withShadows && effects.cardEdgeLight {
                backItems.append(edgeLight(for: card))
            }
        }
        layers.append(Layer(name: "cards-back", items: backItems, shadow: cardShadow))

        var frontItems = [Item(path: frontCard.path, paint: frontCard.paint)]
        if withShadows && effects.cardEdgeLight {
            frontItems.append(edgeLight(for: frontCard, color: Palette.cardBackTop.mixed(with: .white, 0.4)))
        }
        layers.append(Layer(name: "card-front", items: frontItems, shadow: cardShadow))

        layers.append(Layer(name: "card-text", items: textLines.map {
            Item(path: roundedRect($0.rect, radius: $0.rect.height / 2), paint: .solid($0.color))
        }))

        let grassShadow = withShadows && effects.grassShadow ? Shadow(dy: -2, blur: 22, color: Palette.grassShadow) : nil
        layers.append(Layer(name: grassMiddle.name, items: grassMiddle.items,
                            shadow: grassShadow))
        if let row = grassFront {
            layers.append(Layer(name: row.name, items: row.items))
        }
        return layers
    }

    /// A hairline of light along the top of a card, fading out down its sides.
    private func edgeLight(for card: CardArt, color: RGBA = .white) -> Item {
        let shape = continuousRoundedRect(card.frame, radius: card.radius)
        let paint = Paint.linear(
            from: CGPoint(x: 0, y: card.frame.minY), to: CGPoint(x: 0, y: card.frame.minY + 120),
            stops: [GradientStop(0, color.opacity(0.95)), GradientStop(1, color.opacity(0))])
        return Item(path: shape.transformed(card.transform), paint: paint.transformed(card.transform),
                    strokeWidth: 5, clip: card.path)
    }
}
