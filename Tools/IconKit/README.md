# IconKit

Generates Pasto's visual identity: the app icon set and the web exports, from the logo in
`Design/icon/source/logo.png` (their only source); the menu bar glyph, drawn in code (the app's tile with
two leaves cut out of it); and the DMG window background and layout. Only CoreGraphics, ImageIO and AppKit; no
other images or fonts. Output is deterministic: running it twice leaves the working tree unchanged.

Design, construction and screenshots: [`docs/design/icon.md`](../../docs/design/icon.md).

```bash
swift run --package-path Tools/IconKit iconkit all      # everything in the first table
swift run --package-path Tools/IconKit iconkit --help
```

## What it writes

| Command | Destination |
|---|---|
| `app-icon` | `Pasto/Assets.xcassets/AppIcon.appiconset/` (16–512 pt, @1x and @2x, and its `Contents.json`), from the logo |
| `status-item` | `Pasto/Assets.xcassets/StatusItemIcon.imageset/` (18 pt template, @1x and @2x); refuses a glyph with hairlines |
| `dmg` | `Config/dmg-background.png` and `@2x` (660 × 400 pt), over `Config/dmg-texture.png` if present |
| `export` | `Design/icon/export/` (the icon at 1024 and 512 px, favicons 32/180/512, the mark alone as PNG and SVG), from the logo |
| `previews` | `docs/design/img/` (icon sizes, the mark and its traced outline, the menu bar glyph beside SF Symbols, DMG layout) |

`previews --before <.appiconset folder>` also writes a before/after comparison.

Commands used by the scripts (they write nothing in the repository except where stated):

| Command | Used by | What it does |
|---|---|---|
| `dmg-stage <folder>` | `scripts/release.sh` | puts `.background/background.tiff` (1x and 2x) and `.VolumeIcon.icns` (the app icon's renditions) in the folder that becomes the image |
| `dmg-window <volume>` | `scripts/release.sh` | writes the window's `.DS_Store` on the mounted image and flags its custom icon |
| `dmg-inspect <volume> [--preview <png>]` | `scripts/release.sh` | reads the `.DS_Store` back, checks every record and the labels' contrast, and draws a mock-up |
| `import-illustration <png> <folder> <name> [--points WxH] [--crop center\|bottom]` | `scripts/import-illustrations.sh` | checks a 3:2 source illustration, crops the 8:5 part the app shows and writes @1x, @2x and @3x |
| `import-texture <png> <output>` | `scripts/import-illustrations.sh` | checks the DMG texture and stores it at 1320 × 800 (`Config/dmg-texture.png`) |

## How it is built

- `Mark.swift`: the mark lifted off the logo's white background, with a true alpha along its edges.
- `MarkOutline.swift`: the mark's edge traced into cubic curves, each leaf's gradient, and the SVG exports.
- `AppIcon.swift`: the app icon: the macOS grid (824 tile in 1024, continuous corners, shadow), the white tile, and
  the mark on it, optically centred and larger on the small sizes; each size drawn at its own pixel size with the
  tile on whole pixels.
- `StatusGlyph.swift`: the menu bar glyph's geometry, its hairline check and its review sheet beside SF Symbols.
- `Scene.swift`, `Rasterizer.swift`, `Geometry.swift`: a minimal vector model (layers of paths with a solid or
  gradient fill and a per-layer shadow) painted with CoreGraphics, continuous rounded rectangles, and the blades of
  grass of the DMG background (`Blade`, `BladeOutline`).
- `DMGBackground.swift`, `Sheets.swift`: the DMG background and the review sheets.
- `DSStore.swift`, `FinderAlias.swift`, `DMGWindow.swift`: the DMG window's `.DS_Store` (the "Bud1"
  format with its B-tree, following the public notes on the format and checked against files
  Finder writes), the classic alias that points at the background, and writing, reading back and
  drawing it.
- `GeneratedImages.swift`: imports the source illustrations in `Design/generated/`.
