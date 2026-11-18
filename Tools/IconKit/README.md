# IconKit

Generates Pasto's whole visual identity from code: the app icon (classic asset catalog and Icon
Composer document), the menu bar glyph, the DMG window background and the web exports. The design
is clipboard cards sprouting between blades of grass ("pasto" is Spanish for grass). No external
images or fonts, only CoreGraphics and ImageIO. Output is deterministic: running it twice leaves
the working tree unchanged.

Design, palette and screenshots: [`docs/design/icon.md`](../../docs/design/icon.md).

```bash
swift run --package-path Tools/IconKit iconkit all            # everything in the first table
swift run --package-path Tools/IconKit iconkit draft /tmp/x   # quick renders for iterating (leaves the repo alone)
swift run --package-path Tools/IconKit iconkit --help
```

## What it writes

| Command | Destination |
|---|---|
| `app-icon` | `Pasto/Assets.xcassets/AppIcon.appiconset/` (16–512 pt, @1x and @2x, and its `Contents.json`) |
| `icon-composer` | `Pasto/AppIcon.icon/` (`icon.json` and SVG layers in `Assets/`) |
| `status-item` | `Pasto/Assets.xcassets/StatusItemIcon.imageset/` (18 pt template, @1x and @2x) |
| `dmg` | `Config/dmg-background.png` and `@2x` (660 × 400 pt), over `Config/dmg-texture.png` if present |
| `export` | `Design/icon/export/` (PNG 1024 and 512, SVG, favicons 32/180/512 and `favicon.svg`) |
| `previews` | `docs/design/img/` (size sheets, glyph, DMG and the Icon Composer renditions via `ictool`) |

`previews --before <.appiconset folder>` also writes a before/after comparison.

Commands used by the scripts (they write nothing in the repository except where stated):

| Command | Used by | What it does |
|---|---|---|
| `dmg-stage <folder>` | `scripts/release.sh` | puts `.background/background.tiff` (1x and 2x) and `.VolumeIcon.icns` in the folder that becomes the image |
| `dmg-window <volume>` | `scripts/release.sh` | writes the window's `.DS_Store` on the mounted image and flags its custom icon |
| `dmg-inspect <volume> [--preview <png>]` | `scripts/release.sh` | reads the `.DS_Store` back, checks every record and the labels' contrast, and draws a mock-up |
| `import-illustration <png> <folder> <name> [--points WxH] [--crop center\|bottom]` | `scripts/import-illustrations.sh` | checks a 3:2 source illustration, crops the 8:5 part the app shows and writes @1x, @2x and @3x |
| `import-texture <png> <output>` | `scripts/import-illustrations.sh` | checks the DMG texture and stores it at 1320 × 800 (`Config/dmg-texture.png`) |

## How it is built

- `Scene.swift`: a minimal vector model (layers of paths with a solid or gradient fill and a
  per-layer shadow). `Rasterizer` paints it with CoreGraphics and `SVGWriter` serialises it, so PNG
  and SVG come from the same description.
- `PastoIcon.swift`: the palette (`Palette`), the geometry per level of detail (`IconArt.full`,
  `.medium`, `.small`, `.tiny`) and the layers. Blades of grass are `Blade` values (base, width,
  height, lean, stiffness) built in `Geometry.swift`.
- `IconComposer.swift`: writes the `.icon` document (format checked with `ictool`, and with
  `actool` through `scripts/build.sh`).
- `StatusGlyph.swift`, `DMGBackground.swift`, `Sheets.swift`: the glyph, the DMG background and the
  review sheets.
- `DSStore.swift`, `FinderAlias.swift`, `DMGWindow.swift`: the DMG window's `.DS_Store` (the "Bud1"
  format with its B-tree, following the public notes on the format and checked against files
  Finder writes), the classic alias that points at the background, and writing, reading back and
  drawing it.
- `GeneratedImages.swift`: imports the source illustrations in `Design/generated/`.
