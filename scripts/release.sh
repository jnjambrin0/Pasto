#!/bin/bash
# Builds a Pasto release for distribution outside the App Store: Developer ID archive and export,
# signature checks, disk image, notarization, stapling and the Sparkle appcast. Nothing is uploaded.
# Step-by-step guide: docs/RELEASING.md.
#
#   scripts/release.sh <version> [--step <step>] [--notarize] [--dry-run]
#
#   <version>     x.y.z; must equal MARKETING_VERSION in Pasto.xcodeproj
#   --step        archive | export | dmg | notarize | staple | appcast | all (default: all)
#   --notarize    allows the notarize and staple steps, which send the DMG to Apple; without it
#                 `all` stops after the DMG
#   --dry-run     checks the prerequisites and prints the commands instead of running them
#
# Environment:
#   PASTO_TEAM_ID          Apple Developer team whose Developer ID signs the release (default:
#                          DZ97PSDX9S; must match DEVELOPMENT_TEAM in Pasto.xcodeproj and teamID
#                          in Config/ExportOptions.plist)
#   PASTO_BUILD_NUMBER     CFBundleVersion of the build (default: number of commits in HEAD + 1000)
#   PASTO_NOTARY_PROFILE   notarytool keychain profile (default: pasto)
#   PASTO_SPARKLE_ACCOUNT  keychain account of the Sparkle EdDSA key (default: ed25519)
#   PASTO_SPARKLE_BIN      folder with Sparkle's generate_appcast and generate_keys (default: found
#                          in the package artifacts)
#
# The DMG window (background, icon positions, volume icon) is written by Tools/IconKit straight into
# the image's .DS_Store, without Finder; the dmg step checks it and draws a mock-up, dmg-window.png.
# The public URLs come from Config/Release.xcconfig. Outputs go to build/release/<version>/; the
# appcast is assembled in build/release/appcast/, which keeps the previous versions.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

TEAM_ID="${PASTO_TEAM_ID:-DZ97PSDX9S}"
BUNDLE_ID="jnjambrino.Pasto"
NOTARY_PROFILE="${PASTO_NOTARY_PROFILE:-pasto}"
SPARKLE_ACCOUNT="${PASTO_SPARKLE_ACCOUNT:-ed25519}"

usage() { sed -n '5,27p' "$0" | sed -E 's/^# ?//'; exit 2; }
fail() { echo "error: $*" >&2; exit 1; }
note() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }

VERSION=""
STEP="all"
NOTARIZE=0
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --step) [ $# -ge 2 ] || fail "--step needs a value"; STEP="$2"; shift 2 ;;
    --step=*) STEP="${1#--step=}"; shift ;;
    --notarize) NOTARIZE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    -*) fail "unknown option $1" ;;
    *) [ -z "$VERSION" ] || fail "unexpected argument $1"; VERSION="$1"; shift ;;
  esac
done
[ -n "$VERSION" ] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "the version must look like 1.2.3, not '$VERSION'"
case "$STEP" in all|archive|export|dmg|notarize|staple|appcast) ;; *) fail "unknown step '$STEP'" ;; esac

OUT="$ROOT/build/release/$VERSION"
LOGS="$OUT/logs"
DERIVED="$ROOT/build/release/DerivedData"
ARCHIVE="$OUT/Pasto.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/Pasto.app"
DMG_NAME="Pasto-$VERSION.dmg"
DMG="$OUT/$DMG_NAME"
NOTES="$ROOT/docs/release/notes/$VERSION.md"
NOTES_HTML_NAME="Pasto-$VERSION.html"
APPCAST_DIR="$ROOT/build/release/appcast"
BUILD_INFO="$OUT/build-info.env"

# MARK: - Helpers

dry() { [ "$DRY_RUN" = 1 ]; }

# Runs a command that changes something, or prints it on a dry run.
run() {
  if dry; then
    printf '   [dry-run]'
    printf ' %q' "$@"
    echo
  else
    "$@"
  fi
}

# logged <name> <command…>: runs quietly into $LOGS/<name>.log; on failure shows the errors.
logged() {
  local log="$LOGS/$1.log"
  shift
  if dry; then run "$@"; return; fi
  mkdir -p "$LOGS"
  if ! "$@" >"$log" 2>&1; then
    grep -E "error:|\*\* .* FAILED \*\*" "$log" | sed -E "s|$ROOT/||" | sort -u | cut -c1-300 | head -30 >&2 || true
    fail "$1 failed (full log: $log)"
  fi
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }
build_info() { sed -n "s/^$1=//p" "$BUILD_INFO" 2>/dev/null; }
build_setting() { printf '%s\n' "$SETTINGS" | sed -n -E "s/^ +$1 = //p" | head -1; }

require() {  # require <path> <step that makes it>
  dry || [ -e "$1" ] || fail "missing $1: run the $2 step first"
}

# Highest CFBundleVersion already in the local appcast, if any.
latest_published_build() {
  local appcast="$APPCAST_DIR/$APPCAST_NAME"
  [ -f "$appcast" ] || return 0
  grep -oE 'sparkle:version(>|=")[0-9]+' "$appcast" | grep -oE '[0-9]+$' | sort -n | tail -1
}

sparkle_bin() {
  local dir
  for dir in "${PASTO_SPARKLE_BIN:-}" \
             "$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin" \
             "$ROOT/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin" \
             "$ROOT/Packages/PastoKit/.build/artifacts/sparkle/Sparkle/bin"; do
    if [ -n "$dir" ] && [ -x "$dir/generate_appcast" ]; then
      echo "$dir"
      return
    fi
  done
  fail "Sparkle's tools (generate_appcast, generate_keys) were not found: run the archive step first or set PASTO_SPARKLE_BIN"
}

# MARK: - Prerequisites

preflight() {
  local tool
  for tool in xcodebuild xcrun codesign spctl hdiutil ditto shasum file git python3 security; do
    command -v "$tool" >/dev/null || fail "missing tool: $tool"
  done

  SETTINGS="$(xcodebuild -project Pasto.xcodeproj -target Pasto -configuration Release -showBuildSettings 2>/dev/null)" \
    || fail "xcodebuild could not read the project's build settings"
  local project_version
  project_version="$(build_setting MARKETING_VERSION)"
  [ "$project_version" = "$VERSION" ] \
    || fail "MARKETING_VERSION in Pasto.xcodeproj is $project_version, not $VERSION: change it there and commit before building $VERSION"
  # Debug builds are jnjambrino.Pasto.dev; a distribution build must be the published identity.
  local bundle_id
  bundle_id="$(build_setting PRODUCT_BUNDLE_IDENTIFIER)"
  [ "$bundle_id" = "$BUNDLE_ID" ] \
    || fail "the Release configuration builds $bundle_id, not $BUNDLE_ID: check PRODUCT_BUNDLE_IDENTIFIER in Pasto.xcodeproj"
  FEED_URL="$(build_setting PASTO_FEED_URL)"
  DOWNLOAD_BASE_URL="$(build_setting PASTO_DOWNLOAD_BASE_URL)"
  DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL%/}"
  [[ "$FEED_URL" =~ ^https:// ]] || fail "PASTO_FEED_URL in Config/Release.xcconfig is not an https URL: '$FEED_URL'"
  [[ "$DOWNLOAD_BASE_URL" =~ ^https:// ]] || fail "PASTO_DOWNLOAD_BASE_URL in Config/Release.xcconfig is not an https URL: '$DOWNLOAD_BASE_URL'"
  APPCAST_NAME="$(basename "$FEED_URL")"

  # The public half of the key that signs updates. Without it the app cannot verify any update,
  # so a build without it must never reach users: they would be stuck on that version.
  [ -n "$(plist_value "$ROOT/Config/Info.plist" SUPublicEDKey)" ] \
    || fail "SUPublicEDKey is empty in Config/Info.plist. Create the Sparkle key and copy its public half there (docs/RELEASING.md)"

  local identities
  identities="$(security find-identity -v -p codesigning)"
  IDENTITY_HASH="$(printf '%s\n' "$identities" | awk -v team="($TEAM_ID)\"" '/"Developer ID Application: / && index($0, team) { print $2; exit }')"
  [ -n "$IDENTITY_HASH" ] || fail "no \"Developer ID Application\" identity of team $TEAM_ID in the keychain"
  IDENTITY_NAME="$(printf '%s\n' "$identities" | grep "$IDENTITY_HASH" | sed -E 's/.*"(.*)"$/\1/')"
}

# A build reaches users only from a committed tree and once Apple has notarized it.
require_publishable() {
  dry && return 0
  [ "$(build_info DIRTY)" = 0 ] \
    || fail "this build was made from a working tree with uncommitted changes: commit, then run the steps again from archive"
  [ -n "$(plist_value "$APP/Contents/Info.plist" SUPublicEDKey)" ] || fail "the exported app has an empty SUPublicEDKey"
}

# MARK: - Checks

# verify_app [notarized]: the exported app is complete, everything in it carries our signature,
# and Gatekeeper accepts it (as notarized, once stapled).
verify_app() {
  local expect="${1:-signed}"
  local report="$LOGS/verify-app.txt"
  local plist="$APP/Contents/Info.plist"
  mkdir -p "$LOGS"
  : >"$report"
  note "Checking $APP"

  [ "$(plist_value "$plist" CFBundleIdentifier)" = "$BUNDLE_ID" ] || fail "the bundle identifier is not $BUNDLE_ID"
  [ "$(plist_value "$plist" CFBundleShortVersionString)" = "$VERSION" ] || fail "CFBundleShortVersionString is not $VERSION"
  [ "$(plist_value "$plist" CFBundleVersion)" = "$(build_info BUILD)" ] || fail "CFBundleVersion is not $(build_info BUILD)"
  [ "$(plist_value "$plist" SUFeedURL)" = "$FEED_URL" ] || fail "SUFeedURL is '$(plist_value "$plist" SUFeedURL)', not $FEED_URL"
  printf '    version %s (%s), feed %s\n' "$VERSION" "$(build_info BUILD)" "$FEED_URL" | tee -a "$report"

  echo "\$ codesign --verify --deep --strict --verbose=2 Pasto.app" >>"$report"
  codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed "s|$EXPORT/||" | tee -a "$report"

  # Every Mach-O file inside: our Developer ID, our team, a secure timestamp; executables also
  # with the hardened runtime; nothing with get-task-allow (notarization refuses it).
  local file details kind problems=0 count=0
  while IFS= read -r -d '' file; do
    kind="$(file -b "$file")"
    [[ "$kind" == Mach-O* ]] || continue
    count=$((count + 1))
    local name="${file#"$EXPORT"/}" issues=()
    if ! details="$(codesign -dvv "$file" 2>&1)"; then
      issues+=("unsigned")
    else
      grep -q "^Authority=Developer ID Application: .*($TEAM_ID)$" <<<"$details" || issues+=("not signed with our Developer ID")
      grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$details" || issues+=("team is not $TEAM_ID")
      grep -q "^Timestamp=" <<<"$details" || issues+=("no secure timestamp")
      if [[ "$kind" == *executable* ]] && ! grep -q "flags=.*runtime" <<<"$details"; then
        issues+=("no hardened runtime")
      fi
      if codesign -d --entitlements - --xml "$file" 2>/dev/null | grep -q "get-task-allow"; then
        issues+=("has get-task-allow")
      fi
    fi
    if [ ${#issues[@]} -eq 0 ]; then
      printf '    ok    %s\n' "$name" | tee -a "$report"
    else
      problems=$((problems + 1))
      printf '    FAIL  %s: %s\n' "$name" "$(IFS=,; echo "${issues[*]}")" | tee -a "$report"
    fi
  done < <(find "$APP" -type f -print0)
  [ "$problems" -eq 0 ] || fail "$problems of $count code files are not signed as they should be (see $report)"
  echo "    $count code files, all signed by $IDENTITY_NAME with a secure timestamp" | tee -a "$report"

  local assessment
  assessment="$(spctl -a -vv -t exec "$APP" 2>&1 || true)"
  echo "\$ spctl -a -vv -t exec Pasto.app" >>"$report"
  sed "s|$EXPORT/||" <<<"$assessment" | tee -a "$report"
  if [ "$expect" = notarized ]; then
    grep -q "accepted" <<<"$assessment" && grep -q "source=Notarized Developer ID" <<<"$assessment" \
      || fail "Gatekeeper does not accept the app as notarized"
  elif grep -q "accepted" <<<"$assessment"; then
    :
  elif grep -q "source=Unnotarized Developer ID" <<<"$assessment"; then
    echo "    Gatekeeper: Developer ID signature recognised; the app is accepted once notarized" | tee -a "$report"
  else
    fail "Gatekeeper rejects the app for a reason other than missing notarization"
  fi
}

# verify_dmg [notarized]
verify_dmg() {
  local expect="${1:-signed}"
  local report="$LOGS/verify-dmg.txt"
  mkdir -p "$LOGS"
  : >"$report"
  note "Checking $DMG_NAME"
  hdiutil verify -quiet "$DMG" || fail "hdiutil cannot verify $DMG_NAME"
  echo "\$ codesign --verify --strict --verbose=2 $DMG_NAME" >>"$report"
  codesign --verify --strict --verbose=2 "$DMG" 2>&1 | sed "s|$OUT/||" | tee -a "$report"
  local details
  details="$(codesign -dvv "$DMG" 2>&1)"
  grep -q "^Authority=Developer ID Application: .*($TEAM_ID)$" <<<"$details" || fail "the DMG is not signed with our Developer ID"
  grep -q "^Timestamp=" <<<"$details" || fail "the DMG signature has no secure timestamp"
  grep -E "^(Authority=Developer ID Application|TeamIdentifier|Timestamp)" <<<"$details" | sed 's/^/    /' | tee -a "$report"

  local assessment
  assessment="$(spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 || true)"
  echo "\$ spctl -a -vv -t open --context context:primary-signature $DMG_NAME" >>"$report"
  sed "s|$OUT/||" <<<"$assessment" | tee -a "$report"
  if [ "$expect" = notarized ]; then
    grep -q "accepted" <<<"$assessment" && grep -q "source=Notarized Developer ID" <<<"$assessment" \
      || fail "Gatekeeper does not accept the DMG as notarized"
  elif ! grep -q "accepted" <<<"$assessment" && ! grep -q "source=Unnotarized Developer ID" <<<"$assessment"; then
    fail "Gatekeeper rejects the DMG for a reason other than missing notarization"
  fi
}

# MARK: - Steps

step_archive() {
  # The number of commits, above the builds published before the history was restarted (441 was
  # the last one): Sparkle only offers a build whose number is higher than the installed one.
  local build="${PASTO_BUILD_NUMBER:-$(( $(git rev-list --count HEAD) + 1000 ))}"
  [[ "$build" =~ ^[1-9][0-9]*$ ]] || fail "the build number must be a positive integer, not '$build'"
  local latest
  latest="$(latest_published_build)"
  if [ -n "$latest" ] && [ "$build" -le "$latest" ]; then
    fail "build $build is not above $latest, the newest one in $APPCAST_DIR/$APPCAST_NAME: Sparkle would not offer it (set PASTO_BUILD_NUMBER)"
  fi
  local dirty=0
  [ -z "$(git status --porcelain)" ] || dirty=1
  [ "$dirty" = 0 ] || warn "the working tree has uncommitted changes: this build can be tested but not published"

  note "Archiving Pasto $VERSION ($build) from $(git rev-parse --short HEAD)"
  run rm -rf "$OUT"
  run mkdir -p "$LOGS"
  logged archive xcodebuild -project Pasto.xcodeproj -scheme Pasto -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -archivePath "$ARCHIVE" \
    -onlyUsePackageVersionsFromResolvedFile CURRENT_PROJECT_VERSION="$build" clean archive
  dry && return 0
  cat >"$BUILD_INFO" <<EOF
VERSION=$VERSION
BUILD=$build
COMMIT=$(git rev-parse HEAD)
DIRTY=$dirty
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  echo "    $ARCHIVE"
}

step_export() {
  require "$ARCHIVE" archive
  note "Exporting with Developer ID"
  run rm -rf "$EXPORT"
  logged export xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist Config/ExportOptions.plist
  dry || verify_app
}

# Builds Tools/IconKit once per run: it stages the DMG's background and volume icon, writes the
# window's .DS_Store and checks it.
ICONKIT="$ROOT/Tools/IconKit/.build/release/iconkit"
iconkit_ready=0
iconkit() {
  if [ "$iconkit_ready" = 0 ]; then
    logged iconkit swift build -c release --package-path Tools/IconKit
    iconkit_ready=1
  fi
  run "$ICONKIT" "$@"
}

# detach_image <mount point>: unmounts, insisting once if something still holds the volume.
detach_image() {
  run hdiutil detach -quiet "$1" || { sleep 2; run hdiutil detach -quiet -force "$1"; }
}

step_dmg() {
  require "$APP" export
  note "Making $DMG_NAME"
  local stage="$OUT/dmg-stage" image="$OUT/Pasto-rw.dmg" mount="$OUT/dmg-mount"
  [ ! -d "$mount" ] || detach_image "$mount" 2>/dev/null || true
  run rm -rf "$stage" "$image" "$DMG" "$mount"
  run mkdir -p "$stage" "$mount"
  run ditto "$APP" "$stage/Pasto.app"
  run ln -s /Applications "$stage/Applications"
  # .background/background.tiff (660 × 400 pt at 1x and 2x, from Config/dmg-background*.png) and
  # .VolumeIcon.icns.
  iconkit dmg-stage "$stage"
  # Keeps macOS from logging file-system events into the image while it is mounted to write it.
  run mkdir "$stage/.fseventsd"
  run touch "$stage/.fseventsd/no_log"
  local size_mb=40
  dry || size_mb=$(($(du -sm "$stage" | cut -f1) + 20))
  run hdiutil create -quiet -volname Pasto -fs HFS+ -format UDRW -size "${size_mb}m" -srcfolder "$stage" -ov "$image"
  # Mounted where Finder does not look (-nobrowse, own mount point), so only IconKit writes the
  # volume's .DS_Store: window size, no sidebar or toolbar, background, icon size and positions,
  # and the custom volume icon flag.
  run hdiutil attach -quiet -readwrite -noverify -noautoopen -nobrowse -mountpoint "$mount" "$image"
  iconkit dmg-window "$mount"
  detach_image "$mount"
  run hdiutil convert -quiet "$image" -format ULMO -o "$DMG"
  run rm -rf "$stage" "$image" "$mount"
  run codesign --sign "$IDENTITY_HASH" --timestamp "$DMG"
  dry && return 0
  verify_dmg
  inspect_dmg_window
}

# Mounts the finished DMG read-only, out of Finder's sight, reads its .DS_Store back, checks every
# record and draws the window as Finder should show it (dmg-window.png; docs/RELEASING.md).
inspect_dmg_window() {
  local mount="$OUT/dmg-check" report="$LOGS/dmg-window.txt"
  rm -rf "$mount"
  mkdir -p "$mount" "$LOGS"
  note "Checking the DMG window"
  hdiutil attach -quiet -readonly -noverify -noautoopen -nobrowse -mountpoint "$mount" "$DMG"
  local status=0
  "$ICONKIT" dmg-inspect "$mount" --preview "$OUT/dmg-window.png" >"$report" 2>&1 || status=$?
  detach_image "$mount"
  rmdir "$mount" 2>/dev/null || true
  grep -E "FAIL|label \"|iconkit:" "$report" | sed 's/^ */    /' || true
  [ "$status" = 0 ] || fail "the DMG window is not laid out as it should be (full report: $report)"
  echo "    every record checked ($report); look at $OUT/dmg-window.png before publishing"
}

step_notarize() {
  [ "$NOTARIZE" = 1 ] || fail "notarizing sends the DMG to Apple: pass --notarize to do it"
  require "$DMG" dmg
  require_publishable
  local check
  if ! check="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
    if grep -q "No Keychain password item found" <<<"$check"; then
      fail "there are no notarization credentials under the keychain profile '$NOTARY_PROFILE'. Create them once with:

    xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id \"<your Apple ID>\" --team-id $TEAM_ID

It asks for an app-specific password (account.apple.com → Sign-In and Security → App-Specific Passwords)."
    fi
    fail "notarytool cannot use the profile '$NOTARY_PROFILE': $check"
  fi

  note "Notarizing $DMG_NAME (waits for Apple; usually a few minutes)"
  if dry; then
    run xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json
    return
  fi
  local result id status
  result="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json || true)"
  printf '%s\n' "$result" >"$LOGS/notary-submit.json"
  id="$(python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))' <<<"$result" 2>/dev/null || true)"
  status="$(python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))' <<<"$result" 2>/dev/null || true)"
  if [ -n "$id" ]; then
    xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$LOGS/notary-log.json" >/dev/null 2>&1 || true
  fi
  [ "$status" = "Accepted" ] || fail "notarization ended as '${status:-unknown}' (submission ${id:-?}); Apple's log: $LOGS/notary-log.json"
  echo "    accepted, submission $id"
}

step_staple() {
  [ "$NOTARIZE" = 1 ] || fail "stapling follows notarization: pass --notarize to do it"
  require "$DMG" dmg
  note "Stapling the notarization ticket"
  # The DMG's ticket also covers the app inside it; the exported copy is stapled for the record.
  run xcrun stapler staple -q "$DMG"
  run xcrun stapler staple -q "$APP"
  dry && return 0
  xcrun stapler validate -q "$DMG" || fail "stapler cannot validate $DMG_NAME"
  xcrun stapler validate -q "$APP" || fail "stapler cannot validate Pasto.app"
  verify_app notarized
  verify_dmg notarized
}

step_appcast() {
  require "$DMG" dmg
  [ -f "$NOTES" ] || fail "missing release notes: $NOTES"
  require_publishable
  if ! dry; then
    xcrun stapler validate -q "$DMG" \
      || fail "$DMG_NAME is not notarized and stapled: run the notarize and staple steps (--notarize) first"
  fi
  local bin app_key keychain_key build latest
  bin="$(sparkle_bin)"
  app_key="$(plist_value "$APP/Contents/Info.plist" SUPublicEDKey)"
  keychain_key="$("$bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)" \
    || fail "there is no Sparkle signing key for the account '$SPARKLE_ACCOUNT' in the keychain (docs/RELEASING.md)"
  dry || [ "$app_key" = "$keychain_key" ] \
    || fail "the app's SUPublicEDKey ($app_key) is not the public half of the keychain key ($keychain_key): the update would be rejected"
  build="$(build_info BUILD)"
  latest="$(latest_published_build)"
  if [ -n "$latest" ] && [ "$build" -le "$latest" ] && ! grep -q "sparkle:version>$build<" "$APPCAST_DIR/$APPCAST_NAME"; then
    fail "build $build is not above $latest, the newest one in the appcast"
  fi

  note "Updating $APPCAST_NAME"
  run mkdir -p "$APPCAST_DIR"
  run cp "$DMG" "$APPCAST_DIR/$DMG_NAME"
  run python3 -I scripts/release-notes-html.py "$NOTES" "$APPCAST_DIR/$NOTES_HTML_NAME"
  run "$bin/generate_appcast" --account "$SPARKLE_ACCOUNT" --download-url-prefix "$DOWNLOAD_BASE_URL/" \
    --maximum-deltas 0 --embed-release-notes -o "$APPCAST_DIR/$APPCAST_NAME" "$APPCAST_DIR"
  run cp "$APPCAST_DIR/$APPCAST_NAME" "$APPCAST_DIR/$NOTES_HTML_NAME" "$OUT/"
  dry && return 0
  grep -q "url=\"$DOWNLOAD_BASE_URL/$DMG_NAME\"" "$OUT/$APPCAST_NAME" || fail "the appcast has no item pointing at $DOWNLOAD_BASE_URL/$DMG_NAME"
  grep -q "sparkle:version>$build<" "$OUT/$APPCAST_NAME" || fail "the appcast has no item for build $build"
  grep -q "sparkle:edSignature=" "$OUT/$APPCAST_NAME" || fail "the appcast item is not signed"
}

summary() {
  dry && return 0
  echo
  note "Pasto $VERSION — $OUT"
  printf '    build %s, commit %s%s\n' "$(build_info BUILD)" "$(build_info COMMIT | cut -c1-10)" \
    "$([ "$(build_info DIRTY)" = 1 ] && echo ' (uncommitted changes)')"
  local file sums="$OUT/SHA256SUMS"
  : >"$sums"
  for file in "$DMG" "$OUT/$APPCAST_NAME" "$OUT/$NOTES_HTML_NAME"; do
    [ -f "$file" ] || continue
    (cd "$OUT" && shasum -a 256 "$(basename "$file")") | tee -a "$sums" | sed 's/^/    /'
  done
  [ -d "$APP" ] && echo "    app: $APP"
  local reasons=()
  [ "$(build_info DIRTY)" = 0 ] || reasons+=("built from uncommitted changes")
  if [ -f "$DMG" ]; then
    xcrun stapler validate -q "$DMG" 2>/dev/null || reasons+=("DMG not notarized")
  else
    reasons+=("no DMG")
  fi
  [ -f "$OUT/$APPCAST_NAME" ] || reasons+=("no appcast")
  if [ ${#reasons[@]} -eq 0 ]; then
    echo "    ready to publish: upload $DMG_NAME to $DOWNLOAD_BASE_URL/ and $APPCAST_NAME to $FEED_URL"
  else
    echo "    not publishable yet: $(IFS=,; echo "${reasons[*]}" | sed 's/,/, /g')"
  fi
}

# MARK: - Main

preflight
if [ "$STEP" = all ]; then
  step_archive
  step_export
  step_dmg
  if [ "$NOTARIZE" = 1 ]; then
    step_notarize
    step_staple
    step_appcast
  else
    note "Stopping before notarization (pass --notarize to notarize, staple and make the appcast)"
  fi
else
  "step_$STEP"
fi
summary
