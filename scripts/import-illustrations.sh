#!/bin/bash
# Imports the source illustrations in Design/generated/ into the app and the DMG. Each one is
# checked (3:2 canvas, at least 1536 px wide, no transparency), cropped to the 8:5 part the app
# shows and written at @1x, @2x and @3x next to the module that shows it; the DMG texture is
# cropped to the window's proportion and the DMG background is redrawn over it.
# Pictures that are missing are skipped: the app keeps drawing its vector illustration for them.
# Design and crops: docs/design/onboarding-art.md.
#
#   scripts/import-illustrations.sh [folder]     (default: Design/generated)
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:-Design/generated}"
ONBOARDING="Packages/PastoKit/Sources/PastoOnboarding/Resources/Illustrations"
PERMISSIONS="Packages/PastoKit/Sources/PastoPermissions/Resources/Illustrations"
# Every illustration is shown at 8:5; 400 × 250 pt is the permission windows' size, and the @3x
# scale (1200 × 750 px) covers screens that show it larger.
POINTS="400x250"

[ -d "$SOURCE" ] || { echo "error: no folder $SOURCE" >&2; exit 1; }
echo "==> Building IconKit"
swift build -c release --package-path Tools/IconKit >/dev/null
ICONKIT="Tools/IconKit/.build/release/iconkit"

imported=0
missing=()
# import <name> <destination> <crop>: `bottom` keeps the picture's bottom edge (grass or a panel
# running off it), `center` takes the rows from the middle.
import() {
  local name="$1" destination="$2" crop="$3"
  if [ ! -f "$SOURCE/$name.png" ]; then
    missing+=("$name")
    return
  fi
  mkdir -p "$destination"
  "$ICONKIT" import-illustration "$SOURCE/$name.png" "$destination" "$name" --points "$POINTS" --crop "$crop"
  imported=$((imported + 1))
}

echo "==> Illustrations"
import onboarding-intro "$ONBOARDING" bottom
import onboarding-quickstart "$ONBOARDING" bottom
import onboarding-accessibility "$PERMISSIONS" bottom
import onboarding-pasteboard "$PERMISSIONS" bottom
import onboarding-suggestions "$PERMISSIONS" center

echo "==> DMG background"
if [ -f "$SOURCE/dmg-texture.png" ]; then
  "$ICONKIT" import-texture "$SOURCE/dmg-texture.png" Config/dmg-texture.png
  imported=$((imported + 1))
else
  missing+=("dmg-texture")
fi
"$ICONKIT" dmg
"$ICONKIT" previews >/dev/null

echo
echo "imported $imported picture(s)"
if [ ${#missing[@]} -gt 0 ]; then
  echo "missing (vector art stays in use): ${missing[*]}"
fi
echo "next: render and look at them (docs/design/onboarding-art.md), then scripts/build.sh"
