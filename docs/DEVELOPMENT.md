# Developing Pasto

How to build, run and test Pasto, and the rules the code follows. For how the pieces fit together, read
[ARCHITECTURE.md](ARCHITECTURE.md) first; for contribution etiquette, [CONTRIBUTING.md](../CONTRIBUTING.md).

## Contents

- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Code signing](#code-signing)
- [Building and running](#building-and-running)
- [The development build](#the-development-build)
- [Debug launch arguments](#debug-launch-arguments)
- [Tests](#tests)
- [Module rules](#module-rules)
- [Concurrency rules](#concurrency-rules)
- [Code style](#code-style)
- [Localisation](#localisation)
- [The Xcode project](#the-xcode-project)
- [Tools](#tools)
- [Icon, illustrations and sounds](#icon-illustrations-and-sounds)

## Requirements

- A Mac with Apple silicon running **macOS 27** or later.
- **Xcode 27.2** or later (the project uses Xcode 27.2's JSON project format, and the package needs the macOS 27
  SDK and Swift 6.2 tools).
- An Apple ID signed in to Xcode, to sign development builds (a free account works; see [Code signing](#code-signing)).

Sparkle is the only external dependency; Swift Package Manager fetches it on the first build.

## Getting started

```bash
git clone https://github.com/jnjambrin0/Pasto.git
cd Pasto
scripts/test.sh          # unit tests of Packages/PastoKit, in about half a minute
scripts/build.sh         # Debug build of the app
scripts/run.sh --in-memory-store   # install and launch it, without touching any real history
```

Or open `Pasto.xcodeproj` in Xcode, select the **Pasto** scheme and run. For a debug session in Xcode, add launch
arguments under *Product › Scheme › Edit Scheme… › Run › Arguments*.

## Code signing

Debug builds are signed automatically with an **Apple Development** certificate of team `DZ97PSDX9S`, the
maintainer's team (`DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY[config=Debug]` in `Pasto.xcodeproj/project.xcproj`).
Without access to that team, the build fails to sign. You only need to change the team; nothing else is tied to it
for development, and the app needs no provisioning profile.

The cleanest way, which leaves the project file untouched, is a local configuration file that `xcodebuild` (and so
`scripts/build.sh`) reads from the `XCODE_XCCONFIG_FILE` environment variable:

```bash
echo 'DEVELOPMENT_TEAM = <YOUR_TEAM_ID>' > ~/pasto-local.xcconfig
export XCODE_XCCONFIG_FILE=~/pasto-local.xcconfig     # for example in your shell profile
scripts/build.sh
```

Your team ID is shown in Xcode under *Settings › Accounts* (a free Apple ID gives you a *Personal Team*). In Xcode
itself, you can instead pick your team in the **Pasto** target's *Signing & Capabilities* tab; please do not commit
that change.

**Why not sign ad hoc?** It builds (`CODE_SIGN_IDENTITY = -` in the same file), but macOS ties the privacy
permissions Pasto needs (Accessibility, clipboard access, screen recording) to the code signature, and an ad hoc
signature changes with every build: you would have to grant them again after each rebuild. A development
certificate keeps them across rebuilds.

Distribution builds use the maintainer's Developer ID and are only made by `scripts/release.sh`
([RELEASING.md](RELEASING.md)).

## Building and running

| Command | What it does |
|---|---|
| `scripts/build.sh` | Debug build into `build/DerivedData` inside the checkout (each git worktree gets its own); prints only warnings, errors and the result |
| `scripts/build.sh Release` | Optimised build **for measurements only**: it keeps the development identity and signature and has no update feed |
| `scripts/run.sh [arguments…]` | Installs the last build at `~/Applications/Pasto.app` and launches it with `open`, passing the arguments to the app. Only the copy it installed is stopped first, never a release of Pasto that may be running |
| `PASTO_CONFIGURATION=Release scripts/run.sh` | Runs the measurement build instead |
| `scripts/test.sh [swift test options]` | Runs the package's unit tests (`swift test --package-path Packages/PastoKit`) and prints a summary |

Always launch through `scripts/run.sh` (or Xcode). Running the binary directly from a terminal makes macOS attribute
the privacy permissions to the terminal, not to Pasto, which hides permission problems.

`PASTO_DERIVED_DATA` changes where the build goes.

## The development build

Debug builds have their own bundle identifier, **`jnjambrino.Pasto.dev`**, so macOS treats them as a different app
from a released Pasto (`jnjambrino.Pasto`). Pasto names its data folder, its log subsystem and its search index
after its bundle identifier, so the two never share anything:

| | Development | Release |
|---|---|---|
| Data (store, suggestions data, `Diagnostics/`) | `~/Library/Application Support/jnjambrino.Pasto.dev/` | `~/Library/Application Support/jnjambrino.Pasto/` |
| Preferences | `defaults read jnjambrino.Pasto.dev` | `defaults read jnjambrino.Pasto` |
| Search index | `jnjambrino.Pasto.dev.search` | `jnjambrino.Pasto.search` |
| Log | `log stream --predicate 'subsystem == "jnjambrino.Pasto.dev"' --level info` | `… subsystem == "jnjambrino.Pasto"` |
| Permissions | `tccutil reset <service> jnjambrino.Pasto.dev` | `tccutil reset <service> jnjambrino.Pasto` |

- The first launch of a development build shows the welcome and asks for the permissions again: Accessibility
  (to post ⌘V), *Paste from Other Apps* (to read the clipboard) and Screen Recording (suggestions only).
- To replay the first-run flow of one permission: `tccutil reset Accessibility jnjambrino.Pasto.dev`,
  `tccutil reset Pasteboard jnjambrino.Pasto.dev` or `tccutil reset ScreenCapture jnjambrino.Pasto.dev`.
- A development build and a release can run at the same time, but both capture what you copy. For testing, keep
  one running.
- **Shortcuts.** The first launch with a store on disk sets the default shortcuts, ⇧⌘V (panel) and ⇧⌘C (Stack), or
  ⌃⇧⌘V and ⌃⇧⌘C when the defaults are already taken, for example by a running release of Pasto. Change them in
  *Settings › Shortcuts*. In Debug builds only, an empty shortcut still registers ⌃⇧⌘V / ⌃⇧⌘C as a fallback.
- Debug builds never start the updater and never offer to move themselves to Applications.

## Debug launch arguments

Pass them after `scripts/run.sh` (or in the Xcode scheme). They put the app in a known state without synthetic key
presses. **Only Debug builds read them**: a Release build compiles them out (`PastoApp/DebugArguments.swift`).

| Argument | Effect |
|---|---|
| `--in-memory-store` | Keeps the history in memory and leaves the real store untouched. It also skips the single-copy check, the launch record, the welcome, the initial shortcuts and the updater, and puts the suggestions data in `$TMPDIR`. Use it for experiments and measurements |
| `--synthetic-items <n>` | Inserts `n` generated text items (implies `--in-memory-store`), for scale and performance work |
| `--show-panel` | Opens the panel as soon as the app has launched |
| `--frame-log <path>` | Appends one line per second with frame pacing while the panel is open: `frames`, `late` (frames that took more than 1.5 refresh intervals), `longest_ms`, `refresh_ms` |

```bash
scripts/run.sh --synthetic-items 100000 --show-panel --frame-log /tmp/frames.log
```

## Tests

The goal is that tests never slow development down.

1. **Unit tests cover pure logic whose failure would go unnoticed**: type detection, checksums and deduplication,
   query parsing and search windows, retention, the store's membership and undo rules, collection diffs and their
   animation, layout maths, paging and selection, Bézier curves, launch policies, suggestion ranking, string
   catalogs. They use Swift Testing, in-memory stores and temporary settings suites, never your data, and the whole
   suite runs in about half a minute with `scripts/test.sh`.
2. **There are no UI test suites.** Pasto's interface is not automated in tests; check visible changes by hand, in
   light and dark mode and in both languages.
3. **A flaky test is deleted**, not retried or padded with waits. Write tests that are deterministic by
   construction (injected clocks, seeds, in-memory stores).
4. Some test targets contain **renderers** that write PNG files for a person to look at (`IllustrationRenders`,
   `PermissionWindowRenders`). They do nothing unless `PASTO_ILLUSTRATION_RENDERS` names an output folder.

Continuous integration (`.github/workflows/ci.yml`) runs `swift build` and `swift test` for `Packages/PastoKit` on
macOS 27.

## Module rules

- **Layers.** A module may depend only on modules in lower layers ([ARCHITECTURE.md](ARCHITECTURE.md#module-graph)),
  and L3 feature modules never import each other; `PastoApp` connects them. Adding a target or a dependency edge is
  an architecture change: update `Package.swift` and `docs/ARCHITECTURE.md` together and explain why in the pull
  request.
- **Minimal API.** Mark `public` only what another module uses (`package` for what only tests or sibling modules
  need). Types that cross modules are `Sendable` values or protocols.
- **One file, one main type.** No dead code, and no orphan `TODO`s: open an issue instead.
- **Names.** Module names start with `Pasto`. Types are named for what they are in Pasto (`ItemRestorer`,
  `HistoryTailer`), not for the framework they wrap.
- **Numbers live in `…Metrics` types.** Measured values (sizes, margins, durations, curves, limits) go in a
  `…Metrics` type per area (`MainPanelMetrics`, `PicksMetrics`, `RestoreMetrics`…), not scattered through views.
- **Dependency injection.** Long-lived services are created once in `PastoApp/Services.swift` and passed down
  through initialisers.

## Concurrency rules

- Swift 6 language mode in every target, with the upcoming features `ExistentialAny`, `MemberImportVisibility`,
  `NonisolatedNonsendingByDefault` and `InferIsolatedConformances` (`Package.swift`).
  - With `NonisolatedNonsendingByDefault`, a `nonisolated async` function runs on its caller's actor. Mark work that
    must leave the actor `@concurrent`.
  - With `MemberImportVisibility`, import what a file uses, explicitly (`import os` where `Logger` is used).
- UI modules are `MainActor` by default; data and service modules are nonisolated by default.
- **Core Data**: the view context is read-only and lives on the main actor; every write goes through
  `StoreWriter`'s single background context with a `transactionAuthor`. Never let an `NSManagedObject` out of a
  `perform`: return identifiers and `Sendable` values.
- **Pasteboard**: `NSPasteboard` is not declared thread-safe. Every access to the general pasteboard goes through
  `SystemPasteboard`.
- **C callbacks** that arrive on the main thread (Carbon hot keys, display links) enter the main actor with
  `MainActor.assumeIsolated`.
- Long-lived background state belongs to an `actor`.

## Code style

There is no linter; follow the code around you.

- Four spaces, no tabs. Lines up to about 120 columns.
- Doc comments (`///`) on types and on anything whose purpose is not obvious from its name. Comments explain *why*,
  in English.
- Prefer value types and small, explicit types over flags and stringly-typed values.
- Layout in the panel is by frames, without Auto Layout; cells are configured from value models.
- **Logging**: use `Log.logger(<category>)`. Never log clipboard contents. Log app identifiers, search queries and
  file paths with `privacy: .private`.
- **Privacy**: nothing new may leave the Mac. Network access is limited to link previews, link pages opened in a
  preview, and Sparkle; anything else needs discussion first.

## Localisation

Pasto ships in **English** (the source language) and **Spanish**.

- Every module with user-facing text has a string catalog, `Resources/Localizable.xcstrings`; the app target has
  `Pasto/InfoPlist.xcstrings` for `Info.plist` strings.
- Keys are semantic (`stack.button.undo`, `pasteItems.clipboard`). Each module reads them through its own strings
  type (`StackStrings`, `SettingsStrings`…), which repeats the English text as the fallback:

  ```swift
  static var undo: String { localized("stack.button.undo", "Undo") }

  private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
      String(localized: key, defaultValue: english, bundle: .module)
  }
  ```

- **Every key must have an English and a Spanish value, marked as translated, with the same format arguments.**
  `Packages/PastoKit/Tests/PastoFoundationTests/StringCatalogTests.swift` enforces it for every catalog (no missing
  or empty values, no stale keys, matching placeholders), so a missing translation fails `scripts/test.sh`.
- Use the names macOS uses in each language for its own settings and permissions.

## The Xcode project

`Pasto.xcodeproj/project.xcproj` uses Xcode 27.2's JSON project format. Validate any change with
`xcodebuild -list -project Pasto.xcodeproj` and `scripts/build.sh`.

- `Pasto/` is a folder synchronised with the target: new files there join the app without editing the project.
  Almost all code belongs in `Packages/PastoKit`, not in the app target.
- The package is referenced as a local package and its `PastoApp` product is linked into the app.
- Conditional settings use `"KEY[config=Debug]"`. **If the same key also has an unconditional value, the
  unconditional one wins in every configuration**: for a per-configuration value, give one `[config=…]` entry per
  configuration and no plain one (this is how `PRODUCT_BUNDLE_IDENTIFIER` is set).
- The project's default configuration is Release, so the scripts always pass `-configuration`.
- Release-only settings (the public feed and download URLs) live in `Config/Release.xcconfig`; `Config/Info.plist`
  holds the keys the generated `Info.plist` does not.

## Tools

Each tool under `Tools/` is a separate Swift package (except SoundKit, a script) with its own README. Build the
measuring tools in release mode: debug numbers are meaningless.

| Tool | What it is for | How to run | Touches your data or needs permissions? |
|---|---|---|---|
| [`CaptureBench`](../Tools/CaptureBench/README.md) | Measures what heavy content costs Pasto: capturing and restoring large text, images and data, thumbnail decoding, search index fill and queries, idle CPU and wake-ups, link metadata fetching | `cd Tools/CaptureBench && swift run -c release capturebench --help` | No: it uses its own pasteboard, a temporary settings suite, its own search index and `$TMPDIR/capturebench`. `idle` only reads the system clipboard's change count; `link-compare` downloads a list of public pages |
| [`StressKit`](../Tools/StressKit/README.md) | Builds a store the size of a year of heavy use (mixed text, images, links, files and colours, items on pinboards) and measures opening, browsing, retention and erasing on it | `cd Tools/StressKit && swift run -c release pastostress run --count 100000 --work /tmp/pastostress` | No: it works on stores in the folder you give it, each scenario on a clone |
| [`CardGallery`](../Tools/CardGallery/README.md) | Renders sample cards off screen to PNG, for every size class, appearance and state, to review card design without running the app | `cd Tools/CardGallery && swift run CardGallery --out /tmp/cards` | No |
| [`ProbeKit`](../Tools/ProbeKit/README.md) | `pastoprobe`, a command-line probe of a running app: window geometry over time, accessibility trees and diffs, menus, screenshots, frame recordings and traces, pixel and colour analysis, image diffs, synthetic keys, clicks, drags and scrolls, pasteboard inspection. `ProbeTarget` is a small app to paste into | `cd Tools/ProbeKit && swift build -c release && .build/release/pastoprobe help` | Yes: it uses the terminal's Accessibility and Screen Recording permissions (exit code 2 when one is missing), and `seed`, `pb-dump` and `pb-watch` write or read your real clipboard. `--app pasto` targets the development build, `--app pasto-release` an installed release |
| [`IconKit`](../Tools/IconKit/README.md) | Generates the app icon set and the web exports from the icon's artwork, the menu bar glyph, and the disk image background and window; imports painted illustrations; used by `scripts/release.sh` for the disk image | `swift run --package-path Tools/IconKit iconkit --help` | No; it writes into the repository (see below) |
| [`SoundKit`](../Tools/SoundKit/README.md) | Synthesises Pasto's copy and paste sounds | `swift Tools/SoundKit/generate-sounds.swift` (writes `Pasto/Sounds/PastoCopy.aiff` and `PastoPaste.aiff`) | No |

There are no fixed performance budgets in the repository; these tools measure wall time, main-thread CPU, memory
(resident and peak) and disk use so that a change can be compared before and after.

## Icon, illustrations and sounds

Nothing visual is edited by hand:

- **Icon, menu bar glyph, disk image background, web exports**: the app icon's only source is the painted artwork
  `Design/icon/source/app-icon-artwork.png`. `swift run --package-path Tools/IconKit iconkit all` regenerates
  `Pasto/Assets.xcassets/AppIcon.appiconset` and `Design/icon/export/` from it, draws the `StatusItemIcon` image set
  and `Config/dmg-background*.png`, and writes the previews in `docs/design/img/`. The output is deterministic.
  Design and construction: [design/icon.md](design/icon.md).
- **Welcome and permission illustrations**: the painted pictures live in `Design/generated/`;
  `scripts/import-illustrations.sh` checks them, crops them and writes @1x, @2x and @3x into the modules that show
  them, and imports the disk image texture. Each illustration also has a vector fallback drawn in SwiftUI. Details:
  [design/onboarding-art.md](design/onboarding-art.md).
- **Sounds**: `Tools/SoundKit/generate-sounds.swift` synthesises them into `Pasto/Sounds/`.

Run `scripts/build.sh` afterwards to check that the asset catalog and the icon compile.
