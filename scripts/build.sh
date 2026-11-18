#!/bin/bash
# Builds the Pasto app and prints only diagnostics and the result.
#   scripts/build.sh            Debug (default)
#   scripts/build.sh Release    optimised build, for performance measurements only
# DerivedData lives inside the checkout so every git worktree gets its own.
# Distribution builds are made by scripts/release.sh, never by this script.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-Debug}"
DERIVED="${PASTO_DERIVED_DATA:-$PWD/build/DerivedData}"
LOG="$DERIVED/last-build.log"
mkdir -p "$DERIVED"

# Debug builds are jnjambrino.Pasto.dev: their own data, preferences and privacy permissions,
# apart from an installed release (docs/DEVELOPMENT.md). A measurement build keeps
# that identity and the development signature, so the permissions granted to the Debug build
# still apply, and has no update feed, so it never looks for updates.
OVERRIDES=()
if [ "$CONFIGURATION" = Release ]; then
  OVERRIDES=("PASTO_RELEASE_SIGNING_IDENTITY=Apple Development" PASTO_FEED_URL= PASTO_BUNDLE_IDENTIFIER_SUFFIX=.dev)
fi

if xcodebuild -project Pasto.xcodeproj -scheme Pasto -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" -destination 'platform=macOS,arch=arm64' ${OVERRIDES[@]+"${OVERRIDES[@]}"} \
    build >"$LOG" 2>&1; then
  grep -E "warning: " "$LOG" | grep -v -E "appintentsmetadataprocessor|Run script build phase" \
    | sed -E "s|$PWD/||" | sort -u | cut -c1-260 | head -30 || true
  APP="$DERIVED/Build/Products/$CONFIGURATION/Pasto.app"
  echo "BUILD OK → $APP ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist"))"
else
  grep -E "error: " "$LOG" | sed -E "s|$PWD/||" | sort -u | cut -c1-320 | head -40 || true
  echo "BUILD FAILED (full log: $LOG)"
  exit 1
fi
