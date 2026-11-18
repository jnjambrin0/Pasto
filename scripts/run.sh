#!/bin/bash
# Installs the last build at a fixed path and launches it through LaunchServices, so that privacy
# permissions (Accessibility, pasteboard, screen recording) are attributed to Pasto and not to the
# terminal. Arguments are passed to the app (debug arguments: docs/DEVELOPMENT.md).
# PASTO_CONFIGURATION=Release selects the optimised build made by `scripts/build.sh Release`.
#
# These builds are jnjambrino.Pasto.dev (docs/DEVELOPMENT.md): only the copy installed
# here is stopped, never a release of Pasto (jnjambrino.Pasto) that may be running as well.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${PASTO_DERIVED_DATA:-$PWD/build/DerivedData}/Build/Products/${PASTO_CONFIGURATION:-Debug}/Pasto.app"
DESTINATION="$HOME/Applications/Pasto.app"

[ -d "$SOURCE" ] || { echo "No build at $SOURCE — run scripts/build.sh first" >&2; exit 1; }

if pkill -f "^$DESTINATION/Contents/MacOS/Pasto( |$)" 2>/dev/null; then sleep 0.4; fi
rm -rf "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"
open -n "$DESTINATION" --args "$@"
echo "Launched $DESTINATION ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist"))"
