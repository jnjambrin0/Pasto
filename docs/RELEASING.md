# Releasing Pasto

Pasto is distributed outside the Mac App Store: the app is signed with a **Developer ID**, **notarised** by Apple,
shipped in a **disk image**, and kept up to date by **Sparkle 2**. `scripts/release.sh` does all of it and
**uploads nothing**: it leaves the files ready in `build/release/<version>/`, and publishing them is a manual step.

Releasing needs the maintainer's Developer ID certificate, notarisation credentials and Sparkle signing key.
Contributors never need any of this; see [DEVELOPMENT.md](DEVELOPMENT.md) to build and run Pasto locally.

## Contents

1. [One-time setup](#1-one-time-setup)
2. [Prepare the version](#2-prepare-the-version)
3. [Build](#3-build)
4. [Publish](#4-publish)
5. [Check the update from one version to the next](#5-check-the-update-from-one-version-to-the-next)
6. [Rolling back](#6-rolling-back)
7. [Release and development builds side by side](#7-release-and-development-builds-side-by-side)
8. [Pre-release checklist](#8-pre-release-checklist)

## 1. One-time setup

### 1.1 Signing identity

```bash
security find-identity -v -p codesigning
# must list: "Developer ID Application: Jaime Navas (DZ97PSDX9S)"
```

The first signature may ask for permission to use the certificate's private key: choose *Always Allow*.

### 1.2 Notarisation credentials (keychain profile `pasto`)

1. Create an app-specific password at <https://account.apple.com> › Sign-In and Security › App-Specific Passwords.
2. Store it in the keychain under the profile `pasto`:

   ```bash
   xcrun notarytool store-credentials pasto --apple-id "<your Apple ID>" --team-id DZ97PSDX9S
   ```

   It asks for the app-specific password and validates it with Apple before saving it.
3. Check: `xcrun notarytool history --keychain-profile pasto` (an empty list the first time, and no error).

With an App Store Connect API key instead:
`xcrun notarytool store-credentials pasto --key AuthKey_<ID>.p8 --key-id <ID> --issuer <UUID>`.
To use another profile name, set `PASTO_NOTARY_PROFILE=<name>`.

### 1.3 Sparkle key

Updates are signed with an EdDSA key. The **private** half lives only in the login keychain (item
`https://sparkle-project.org`, account `ed25519`); the **public** half is `SUPublicEDKey` in `Config/Info.plist` and
travels inside every installed copy of Pasto.

Sparkle's tools are in `build/release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/` after the archive
step (or in `Packages/PastoKit/.build/artifacts/sparkle/Sparkle/bin/` after `scripts/test.sh`). Below, `BIN` is that
folder.

```bash
"$BIN/generate_keys" -p        # prints the keychain's public key: it must match SUPublicEDKey
```

- **Back it up** (essential: if the private key is lost, installed copies will never accept another update):
  `"$BIN/generate_keys" -x ~/Desktop/pasto-sparkle-key`, store the contents in a password manager and delete the
  file.
- **Another Mac**: `"$BIN/generate_keys" -f <file>` imports the private key.
- **No key at all** (a new Mac with no backup): `"$BIN/generate_keys"` creates one in the keychain and prints the
  public half; copy it into `SUPublicEDKey` in `Config/Info.plist` and commit. For a dedicated account, use
  `generate_keys --account pasto` and publish with `PASTO_SPARKLE_ACCOUNT=pasto`.
- **Never change the key after the first public release**: installed copies only accept updates signed with the
  key they carry.

`scripts/release.sh` stops if `SUPublicEDKey` is empty and, when it builds the appcast, if it does not match the
keychain's key.

### 1.4 Public addresses

They are set in a single place, `Config/Release.xcconfig`:

| Setting | Value | What it is |
|---|---|---|
| `PASTO_FEED_URL` | `https://pasto.jnjambrino.com/appcast.xml` | The appcast address, written into every copy's `Info.plist` as `SUFeedURL` |
| `PASTO_DOWNLOAD_BASE_URL` | `https://pasto.jnjambrino.com/downloads` | The public folder of the disk images; the appcast points at `<base>/Pasto-<version>.dmg` |

Both must be `https`. The feed URL is baked into every installed copy: if it ever changes, the old address must
keep serving (or redirecting) for good.

## 2. Prepare the version

Pasto follows [Semantic Versioning](https://semver.org): `x.y.z`.

1. Set `MARKETING_VERSION` to `x.y.z` in `Pasto.xcodeproj/project.xcproj` (target `Pasto`). The script refuses to
   build if they differ.
2. Write the notes in `docs/release/notes/x.y.z.md`. `scripts/release.sh` reads them from exactly that path,
   converts them to HTML with `scripts/release-notes-html.py` and embeds them in the appcast, so keep to what the
   converter supports: `#`–`###` headings, `-` lists, paragraphs, **bold**, *italic*, `code` and links. Add the same
   changes to [CHANGELOG.md](../CHANGELOG.md), grouped by kind.
3. Commit. A version meant for publishing is built from a clean tree: the script records it, and refuses to
   notarise a build or make its appcast otherwise.
4. The build number (`CFBundleVersion`) is the number of commits in `HEAD` (`git rev-list --count HEAD`), so it
   grows by itself. To force another, set `PASTO_BUILD_NUMBER=<n>`. It must be greater than the newest build in
   the appcast, or Sparkle will not offer the version; the script checks this.

## 3. Build

A dry run checks the prerequisites and prints the commands without running them:

```bash
scripts/release.sh x.y.z --notarize --dry-run
```

Everything at once (5–10 minutes, mostly waiting for Apple):

```bash
scripts/release.sh x.y.z --notarize
```

Or step by step; each step starts from what the previous one left, and can be repeated:

| Step | Command | What it does |
|---|---|---|
| archive | `scripts/release.sh x.y.z --step archive` | Deletes `build/release/x.y.z/` and runs `xcodebuild clean archive` in Release, with the package versions pinned in `Package.resolved` |
| export | `--step export` | Exports with Developer ID (`Config/ExportOptions.plist`) and checks the app: `codesign --verify --deep --strict`; every code file signed with the team's Developer ID and a secure timestamp; hardened runtime on executables; no `get-task-allow`; `spctl` |
| dmg | `--step dmg` | Creates `Pasto-x.y.z.dmg` (volume *Pasto*: the app, a link to `/Applications`, the background and the volume icon), writes the window into its `.DS_Store` without Finder, signs it, checks it and draws the mock-up `dmg-window.png` |
| notarize | `--step notarize --notarize` | Sends the disk image to Apple with the `pasto` profile and waits; saves Apple's log in `logs/notary-log.json` |
| staple | `--step staple --notarize` | Staples the ticket to the disk image and to the exported app; `spctl` must accept both as *Notarized Developer ID* |
| appcast | `--step appcast` | Adds the version to the appcast with Sparkle's `generate_appcast` (EdDSA signature, embedded notes) |

`scripts/release.sh --help` prints every option. The script also reads these environment variables:

| Variable | Default | What it sets |
|---|---|---|
| `PASTO_TEAM_ID` | `DZ97PSDX9S` | The team whose Developer ID signs the release; must match `DEVELOPMENT_TEAM` in the project and `teamID` in `Config/ExportOptions.plist` |
| `PASTO_BUILD_NUMBER` | commits in `HEAD` | `CFBundleVersion` |
| `PASTO_NOTARY_PROFILE` | `pasto` | The `notarytool` keychain profile |
| `PASTO_SPARKLE_ACCOUNT` | `ed25519` | The keychain account of the Sparkle signing key |
| `PASTO_SPARKLE_BIN` | found in the package artifacts | The folder with Sparkle's `generate_appcast` and `generate_keys` |

### The disk image window

Neither Finder nor the Automation permission is involved: `Tools/IconKit` (built the first time, in a few seconds)
prepares the contents and writes the window straight into the volume's `.DS_Store`.

1. `iconkit dmg-stage` writes `.background/background.tiff` (`Config/dmg-background.png` and its `@2x` in a single
   two-resolution TIFF, which is how Finder takes a Retina background) and `.VolumeIcon.icns` (the icon at every
   size). `.fseventsd/no_log` keeps macOS from logging file system events inside the image.
2. `hdiutil create` (HFS+, read-write) and `hdiutil attach -nobrowse` at a mount point inside
   `build/release/x.y.z/`: Finder does not see the volume, so nothing else writes its `.DS_Store`.
3. `iconkit dmg-window` writes a 660 × 400 pt window (660 × 432 with macOS 27's title bar) with no sidebar,
   toolbar, status bar or path bar; a 128 pt icon view with 13 pt labels and no automatic arrangement; the app at
   (170, 186) and `Applications` at (490, 186) (icon centres); the background linked with a classic alias; and the
   custom volume icon flag.
4. `hdiutil convert` to ULMO (compressed, read-only), then signing.
5. `iconkit dmg-inspect` mounts the final image read-only, reads the `.DS_Store` back and checks every record:
   window size, hidden bars, icon view, sizes and positions, that the background alias resolves to the real file
   on the volume, that the TIFF has both resolutions, the `/Applications` link, the volume name and icon. It also
   checks that **labels read in both appearances**: Finder draws them black in light mode and white in dark mode
   without adapting the background, so it measures the contrast under each label with both colours (at least 4:1).
   If anything fails, the step fails. The full report is `logs/dmg-window.txt`.

**Look at it before publishing.** Open `build/release/x.y.z/dmg-window.png`: it is the window as Finder will draw
it from the recorded settings (background, the volume's real icons in place, labels), light on top and dark below.
The meadow and the arrow between Pasto and Applications must show, both icons standing on the hill, the labels
readable and nothing cut off.

Optionally, the real test in Finder (the one thing the mock-up cannot guarantee): double-click the disk image and
check that the window opens by itself, with no bars, the whole background and the icons in place, in light and dark
mode, and that the volume icon on the desktop and in the sidebar is Pasto's. Eject it afterwards.

Only the disk image is notarised: its ticket also covers the app inside, and Gatekeeper uses it when the app is
copied to Applications.

### Output (`build/release/x.y.z/`)

| File | Purpose |
|---|---|
| `Pasto-x.y.z.dmg` | What users download |
| `appcast.xml` | The complete feed, with this version and the previous ones |
| `Pasto-x.y.z.html` | The notes as HTML (already embedded in the appcast) |
| `SHA256SUMS` | Checksums of the above |
| `Pasto.xcarchive` | Keep it outside `build/`: it holds the dSYMs needed to symbolicate crash reports |
| `dmg-window.png` | Mock-up of the disk image window, light and dark |
| `export/Pasto.app`, `logs/`, `build-info.env` | The stapled app, the logs, and the version, build and commit |

`build/release/appcast/` is the appcast's workspace: it accumulates the disk images and `appcast.xml` from one
version to the next (`generate_appcast` keeps the three newest and moves older ones to `old_updates/`). When
releasing from another clone, first copy the published `appcast.xml` there.

## 4. Publish

1. Upload `Pasto-x.y.z.dmg` to `PASTO_DOWNLOAD_BASE_URL/Pasto-x.y.z.dmg` as is (never recompress it: the appcast
   carries its size and signature).
2. Check that it downloads whole: `curl -sI <url>` returns 200 and a `content-length` equal to the appcast's
   `length`.
3. Upload `appcast.xml` to `PASTO_FEED_URL` **after** the disk image, so the feed never points at a missing file.
4. Point the website's download link at the new disk image.
5. Tag the commit and push the tag: `git tag -a vx.y.z -m "Pasto x.y.z"` and `git push origin vx.y.z`.
6. Create the GitHub release for the tag, with the notes from `docs/release/notes/x.y.z.md` and the disk image
   attached (the same file, unchanged).

## 5. Check the update from one version to the next

### Before publishing, locally

With the previous version installed in `/Applications` and the new one built and notarised:

```bash
TEST=~/Desktop/pasto-update-test && mkdir -p "$TEST"
cp build/release/x.y.z/Pasto-x.y.z.dmg build/release/x.y.z/Pasto-x.y.z.html "$TEST/"
"$BIN/generate_appcast" --download-url-prefix http://localhost:8000/ --embed-release-notes \
  --maximum-deltas 0 -o "$TEST/appcast.xml" "$TEST"
cd "$TEST" && python3 -m http.server 8000
```

In another terminal:

```bash
defaults write jnjambrino.Pasto SUFeedURL http://localhost:8000/appcast.xml   # the preference overrides Info.plist
open /Applications/Pasto.app
```

1. Pasto menu › *Check for Updates…*: Sparkle's window comes to the front and offers `x.y.z` with its notes.
2. *Install Update*: it downloads, Pasto quits and reopens by itself.
3. *About Pasto* shows `x.y.z`; the permissions (Accessibility, clipboard access) are still granted, because the
   signature is the same.
4. Scheduled check: `defaults delete jnjambrino.Pasto SULastCheckTime`, reinstall the previous version and open
   it: the update alert appears a few seconds after launch.
5. When done: `defaults delete jnjambrino.Pasto SUFeedURL` and stop the server.

### After publishing

On a Mac with the previous version: *Check for Updates…* offers the new one. A clean download from the website
opens without Gatekeeper warnings (`spctl -a -vv /Applications/Pasto.app` reports
`source=Notarized Developer ID`).

## 6. Rolling back

Sparkle never offers a version whose `CFBundleVersion` is lower than the installed one, so a bad version is fixed
forwards:

1. **Stop the rollout**: upload the previous version's `appcast.xml` again (`build/release/<previous>/appcast.xml`)
   or remove the bad `<item>` by hand. Whoever has not installed it will not get it. Point the website's download
   link back at the previous disk image.
2. **Fix it for those who already have it**: publish a new version (`x.y.z+1`) with the fix, or with the good
   version's code, and a higher build number. Never reuse a version or build number, and never change the Sparkle
   key.
3. If the problem is in signing or notarisation and the disk image does not open: withdraw it, fix it, and repeat
   the steps from `archive`.

## 7. Release and development builds side by side

- The Developer ID copy is `jnjambrino.Pasto`; the Debug build is `jnjambrino.Pasto.dev`, signed with an *Apple
  Development* certificate. macOS treats them as two apps: each has its own data, preferences, search index and
  permissions (Accessibility, clipboard access, screen recording), granted once to each. Both can run at the same
  time, but both capture what you copy: for testing, run only one.
- `scripts/build.sh Release` (for measurements) is **not** a distribution build: it keeps the development identity
  and signature (`jnjambrino.Pasto.dev`), so it shares the Debug build's permissions and data, and has no feed, so
  it never looks for updates.
- Debug builds and runs with `--in-memory-store` never start the updater.

## 8. Pre-release checklist

Run it **before publishing every version**, on the final disk image (Developer ID signed, notarised and stapled),
never on a development build. If a step fails, the version does not ship: fix it and run the list again. Steps
marked **[major]** are needed for a first or major release, or when what they test has changed.

**Setup.** Use a fresh macOS user account (or, better, another Mac) for the clean-install pass: on the development
account, the release does not look the way a new user will see it. Keep
`log stream --predicate 'subsystem == "jnjambrino.Pasto"' --level info` open. Alternate the account language
between English and Spanish from one release to the next (both for a major release).

### 8.1 Artefact (on the development Mac)

- [ ] `CFBundleShortVersionString` is the announced version and `CFBundleVersion` is **higher** than the previous
  published build: `plutil -p Pasto.app/Contents/Info.plist | grep -E 'CFBundle(Short)?Version'`.
- [ ] `LSMinimumSystemVersion` matches what the website says.
- [ ] `NSHumanReadableCopyright` is set; `CFBundleLocalizations` includes `en` and `es`.
- [ ] `CFBundleIdentifier` is `jnjambrino.Pasto` (never `jnjambrino.Pasto.dev`).
- [ ] `codesign --verify --deep --strict --verbose=2 Pasto.app` passes; `codesign -dvv Pasto.app` shows
  `Authority=Developer ID Application`, the hardened runtime flag and team `DZ97PSDX9S`.
- [ ] `codesign -d --entitlements - Pasto.app` does **not** contain `com.apple.security.get-task-allow`.
- [ ] `xcrun stapler validate Pasto-x.y.z.dmg` and `spctl -a -vvv -t install Pasto-x.y.z.dmg` report `accepted`,
  `source=Notarized Developer ID`.
- [ ] `lipo -info Pasto.app/Contents/MacOS/Pasto` reports `arm64`.
- [ ] No developer paths or debug switches in the binary: `strings -a Pasto.app/Contents/MacOS/Pasto | grep -c /Users/`
  is 0, and `grep -E -- '--(in-memory-store|synthetic-items|frame-log|show-panel)'` finds nothing.
- [ ] Every `PastoKit_*.bundle` has an `es.lproj`; the acknowledgements (Sparkle's licence) are in the app.
- [ ] `scripts/test.sh` passes.

### 8.2 Clean install [major]

- [ ] The test account has no `~/Library/Application Support/jnjambrino.Pasto`, no
  `~/Library/Preferences/jnjambrino.Pasto.plist` and no Pasto entries in *Privacy & Security*.
- [ ] Download the disk image **from the public website** with Safari (so it is quarantined), not by AirDrop or
  a network share.
- [ ] Opening the disk image shows Pasto's window with no Gatekeeper warning.
- [ ] Opening Pasto straight from the disk image offers to move it to Applications. *Move* puts it in
  `/Applications`, relaunches, and the disk image can be ejected; *Don't Move* explains that it cannot update or
  open at login from there. Same prompt for a copy opened from `~/Downloads` (a translocated path).
- [ ] Dragged to Applications and opened, the only system prompt is the usual "downloaded from the Internet".
- [ ] No Dock icon except during the welcome; the menu bar icon appears when it ends.

### 8.3 Welcome and permissions

- [ ] The welcome window comes to the front over other apps; ⌘W does not close it; ⌘Q quits, and the next launch
  resumes at the same step.
- [ ] Quick Start shows the real activation shortcut (⇧⌘V, or the alternative if ⇧⌘V is taken, with an
  explanation).
- [ ] *Open at login* on: *System Settings › General › Login Items* lists Pasto pointing at `/Applications/Pasto.app`.
- [ ] Steps: intro → paste into other apps → clipboard → suggestions (only where Apple Intelligence is possible) →
  Quick Start. Each click moves on without a noticeable wait.
- [ ] Accessibility step: *Allow* shows the system prompt; after enabling Pasto in System Settings and coming back,
  the row turns to a check and the step moves on by itself. *Not Now* leaves the direct-paste notice card in the
  panel.
- [ ] Clipboard step: the row shows what System Settings says (Ask / Deny / Allow) and follows changes made there.
- [ ] Suggestions step with real permissions: allow screen recording, choose *Quit & Reopen* in System Settings;
  Pasto comes back by itself **at the suggestions step** with the permission shown as granted; the confirmation
  capture asks macOS once, and opening the panel over another app with suggestions on shows no further prompt.
- [ ] Quitting Pasto right after a permission request does **not** reopen it.
- [ ] Without Accessibility, Return on a card asks whether to allow pasting; *Copy* leaves the item on the
  clipboard; *Don't ask again* switches to copy-only mode.
- [ ] After the welcome the panel opens once, with the right notice cards, the tour of tips (Next, Skip, Done) and
  the welcome content: three notes in the history and a red *Pasto Links* pinboard whose links show Pasto's icon
  even offline. Deleted, they never come back. In a Spanish account, all of it is in Spanish.
- [ ] *Help › Show Tips* starts the tour again; after the tour, relaunching shows no tips.
- [ ] With VoiceOver, each tip is read as "title. text" and its buttons are reachable; with Reduce Motion it only
  fades.

### 8.4 Language [both for a major release]

- [ ] Spanish account: panel, menu bar menu, context menus, settings, welcome, permission windows, Stack, preview,
  on-screen notices and About are in Spanish, including the system's screen recording prompt text.
- [ ] English account: everything in English.

### 8.5 Capture

- [ ] Copy plain text, rich text (Notes, Pages), a link (Safari), an image (Preview), a screenshot to the clipboard
  (⌃⇧⌘4), a file and several files (Finder) and a colour: each appears first, with the right card and source app
  icon.
- [ ] A password copied from Passwords, 1Password or Keychain Access does **not** appear.
- [ ] Copying the same text twice gives one card, moved to the front.
- [ ] Pause (menu › Pause): copies are not captured, the icon shows it, and capture resumes afterwards.
- [ ] Offline: copying a link blocks nothing; the card has no metadata.

### 8.6 Paste

- [ ] The activation shortcut works from Safari, TextEdit, Notes, Terminal, Xcode and a full-screen app, and the
  panel appears on the active display and Space.
- [ ] Return pastes into the target app; so do ⌘1…⌘9, ⇧Return (plain text), double-click and dragging a card out.
- [ ] *Paste items: To the clipboard* → Return only copies and shows the notice with *Enable direct paste ›*.
- [ ] ⌘C copies and closes; Esc and ⌘W close.
- [ ] ⌘Z restores a deleted card; deleting, renaming and pinning three cards quickly, each ⌘Z undoes one, last first,
  and ⇧⌘Z redoes them.
- [ ] Home and End go to the first and last card; Page Up and Page Down move a screen (with ⇧, they extend the
  selection).

### 8.7 Search

- [ ] Typing in the panel searches live; filters by type, app, date and pinboard; the filter browser.
- [ ] Text inside an image copied a few minutes ago is found.
- [ ] Copy a unique string (for example `pasto-test-7391`), wait a minute, and search for it in system Spotlight
  (⌘Space): it must **not** appear.

### 8.8 Pinboards, Stack, preview, editing

- [ ] Create a pinboard (+ or ⇧⌘N), rename, recolour, reorder tabs, pin by dragging and from the menu, ⌘← / ⌘→
  between tabs.
- [ ] Deleting a pinboard whose items are also in the history leaves them in the history.
- [ ] Stack: global shortcut (⇧⌘C or its alternative), add from the panel, drag, paste in order with ⌘V in the target
  app, *Paste All* (⌃⌥⌘V), reverse order, close.
- [ ] Space: preview of text, link (page loaded), image, colour and file; editing text and rotating an image; Save
  and Cancel; ⌘N *New Text Item*.
- [ ] With the preview open, → to a card that is off screen scrolls the strip and the preview follows it.
- [ ] About: name, *Version X.Y (build)*, copyright and the acknowledgements.
- [ ] Help: *Getting Started* shows the welcome from the start; *Keyboard Shortcuts* opens *Settings › Shortcuts*;
  *Acknowledgements* opens the licences.
- [ ] *Help › Report a Problem…*: *Write Email* opens Mail with the subject and, at the end of the body, the Pasto
  and macOS versions and the Mac model; *Open Contact Page* opens the website's contact page with the same; with
  the box ticked, Finder shows `Diagnostics/` with the session's `log-<date>.txt` selected, with `<private>` in place
  of private values. Nothing leaves the Mac without the user sending it.
- [ ] MetricKit: `kill -SEGV $(pgrep -x Pasto)`, relaunch and wait (macOS delivers it on a later launch, which can
  take a while): a `report-<date>.json` appears in `Diagnostics/`.
- [ ] Alerts (delete items, erase history, move to Applications, store failure), About, the welcome and the
  permission windows show Pasto's icon, not the generic one.
- [ ] Stack with VoiceOver: each row offers Delete, Move Up and Move Down, and VO-Space pastes it.

### 8.9 Suggestions (on a Mac with Apple Intelligence on)

- [ ] The suggestions button shows; without permission it leads to the screen recording window; after granting and
  *Quit & Reopen*, Pasto comes back, and opening the panel over Mail, Terminal or a web form gives sensible
  suggestions with no permission prompt.
- [ ] Once granted and confirmed, nothing shows the screen access window again.
- [ ] Without the permission, the strip explains what is missing and does not repeat the system dialog.
- [ ] The button's menu › *Turn Off…* explains how to turn suggestions back on (*Settings › Intelligence*).
- [ ] On a Mac without Apple Intelligence (or with it off): no button, and *Settings › Intelligence* explains why.
- [ ] *Settings › General › Erase History* also deletes `paste-journal.jsonl`, `item-classes.jsonl` and
  `Diagnostics/suggestion-log.jsonl`.

### 8.10 Settings

- [ ] Each pane opens centred and active: General (open at login, sounds, paste items, plain text, keep history
  with the warning for *Unlimited*, erase history), Intelligence, Privacy (ignored apps, transient and confidential
  content, link previews, screen sharing, remove all data), Shortcuts (record, conflicts, clear, reset).
- [ ] Turning *Open at login* off in System Settings is reflected in Pasto's settings; if the system blocks it,
  Pasto offers to open System Settings.
- [ ] *Privacy › Remove all data* (on a test account): Pasto quits; its `Application Support`, `Caches`, `WebKit`
  and `HTTPStorages` folders are in the Trash, the preferences file is gone, the login item is removed, and the
  next launch is a first launch.
- [ ] A saved shortcut that another app has taken is reported by a *Shortcut in Use* card with *Change…*, which opens
  *Settings › Shortcuts*.

### 8.11 Environment

- [ ] Two displays: the panel appears on the active one; reopen after moving focus; disconnect a display with the
  panel open.
- [ ] Spaces and full screen: open the panel over a full-screen app and switch Spaces with it open.
- [ ] Sleep and wake with the panel open and with a pause running; capture continues after waking.
- [ ] Fast user switching: with Pasto open in both accounts, each captures its own copies; the shortcut only acts in
  the active session.
- [ ] Light and dark mode; Reduce Motion (no scrolling, deleting or pasting animations; density changes are
  immediate) and Increase Contrast (stronger text on light card headers and empty states, updating live).
- [ ] VoiceOver on cards: VO-Space pastes; the actions menu offers Copy, Preview, Delete and Pin (and Unpin where it
  applies); ⌃Return opens the context menu.
- [ ] Keyboard navigation (System Settings › Keyboard): Tab reaches the toolbar buttons, Space and Return press them,
  and the focus ring follows; with the setting off, Tab does not stop on them.
- [ ] VoiceOver on the toolbar and search: tabs read as "<name>, N items"; the search field, tokens, suggestions and
  result counts are announced; the filter browser has headings.
- [ ] *Keep history* slider with the arrow keys or VoiceOver: no alert per step; the value applies after a pause or
  on leaving the control, and only then asks before deleting.
- [ ] Failing writes (on a test account, make `Pasto.sqlite-wal` immutable with `chflags uchg`, or fill the disk) and
  copy three times: a *Pasto Can't Save What You Copy* card appears with *Storage…*; undo the block and copy again:
  the card goes away.
- [ ] Opening Pasto from Finder while it runs shows the panel or Settings, never nothing.
- [ ] A second copy from another path (`open -n` on a copy on the Desktop) quits within about 3 s and the first one
  shows its panel; two copies opened in the same instant leave exactly one running.
- [ ] A new version opened from its disk image while the old one runs: *Move* → *Replace* leaves the new one in
  `/Applications`, running.
- [ ] Launch alerts come to the front over other apps, also when Pasto starts as a login item.
- [ ] Hiding the menu bar icon from *System Settings › Menu Bar*: the shortcut still works and reopening the app
  gives access to Settings.

### 8.12 Update from the previous version

- [ ] On the test account, install the previous published version, finish the welcome and create data: 30 items of
  several types, two pinboards with items, a custom shortcut, an ignored app, *Keep history* at a week.
- [ ] *Check for Updates…* (or wait for the automatic check) installs the new version and relaunches it from
  `/Applications`.
- [ ] Afterwards, all data, pinboards, settings and shortcuts are intact; the welcome and the welcome content do
  **not** come back; permissions are still granted; the login item still points at `/Applications`.
- [ ] If the data model changed: the store migrates without loss, and an unreadable store leads to the recovery
  alert, never to a crash loop.
- [ ] The same from the version before the previous one, if there is one.

### 8.13 Uninstall

- [ ] Follow the manual uninstall in [PRIVACY.md](PRIVACY.md#deleting-your-data).
- [ ] Nothing is left: `ls ~/Library/{Application\ Support,Preferences,Caches,WebKit,HTTPStorages} | grep -i pasto`
  finds nothing; Login Items and Privacy & Security have no Pasto.
- [ ] System Spotlight still does not return the unique string from 8.7.

### 8.14 Performance and logging

- [ ] Activity Monitor with the panel closed for 5 minutes: CPU close to 0 %, memory around 100 MB, low energy
  impact.
- [ ] Opening the panel with 1,000+ items is smooth; search answers in under a second.
- [ ] The whole session's `log stream` shows no copied content (text, full URLs, file paths) in clear text.
- [ ] No new `.ips` files for Pasto in `~/Library/Logs/DiagnosticReports/`.
- [ ] `log show --last 10m --predicate 'subsystem == "jnjambrino.Pasto" && category == "app"'` lists the
  *Launch phase* lines up to `ready`; `Diagnostics/last-launch.json` ends in `ready`; there is no `launch-*.json`.
- [ ] `pkill -9 -x Pasto` during a first-launch welcome and reopen: a `Diagnostics/launch-<date>.json` reports the
  interrupted launch. Quitting with ⌘Q during the welcome and reopening leaves no such report.

### 8.15 Publication

- [ ] The release notes match the website (macOS requirement, permissions, privacy).
- [ ] The website links the new disk image, the feed announces the version and its EdDSA signature validates.
- [ ] Tag `vx.y.z` is on the exact commit of the build, and the GitHub release has the same notes and disk image.
