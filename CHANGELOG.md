# Changelog

All notable changes to Pasto are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Pasto uses [Semantic Versioning](https://semver.org).

The notes users see in the update window come from `docs/release/notes/<version>.md`, which `scripts/release.sh`
embeds in the update feed. This file collects the same notes, grouped by kind of change.

## [Unreleased]

### Added

- The source code is public under the MIT licence, with guides to the architecture, development and releases.

## [1.0.6] - 2026-11-18

### Changed

- **New logo**: two leaves of grass, green on a white tile. It is the app's icon everywhere, from the Dock to the
  disk image, and the picture the menu bar glyph has shown since 1.0.4, in colour.

## [1.0.5] - 2026-11-18

### Fixed

- **Link previews no longer keep a frozen spinner**: the loading spinner stayed in the middle of the page after it
  had loaded. It now goes away, and a page that keeps loading is shown after a moment instead of waiting for it to
  finish.

## [1.0.4] - 2026-11-18

### Changed

- **A new icon**: three frosted cards rising from the grass. At the smallest sizes, such as in Finder's lists, it
  shows the front card and the grass up close, so it stays recognisable.
- **A new menu bar icon**: Pasto's tile with two leaves cut out of it, sharp on every display and sized like the
  system's own icons beside it. The Stack panel's title shows it too.
- *Help › Report a Problem…* writes to hello@jnjambrino.com.

### Fixed

- **The Stack stays on screen**: with three or more items the panel could grow past the bottom of the screen and
  hide its last rows. It now moves up as it grows.

## [1.0.3] - 2026-11-18

A better first run.

### Added

- **A new welcome**: Pasto now sets everything up before you start. Pasting into other apps, clipboard access and
  smart suggestions each have their own step, with their state shown live. Every step has its own illustration,
  and moving between steps is instant.
- **Never an empty panel**: after the welcome, your history starts with three short notes on how to paste, search
  and pin, and a pinboard with links to Pasto's site, help and release notes. Delete them whenever you like; they
  do not come back.
- **Tips in the panel**: the first time you open Pasto, five short labels point out search, pinboards, suggestions
  and the shortcuts on each card. *Help › Show Tips* shows them again.
- **A proper installer window**: the disk image now opens with its background, the app and the Applications folder
  in place.

### Fixed

- **Screen recording without the dead end**: when macOS quits Pasto after you allow screen recording, Pasto comes
  back by itself, where you left it, and no longer asks again for a permission you already gave.
- **Safer launches**: start-up alerts always come to the front, two copies of Pasto can no longer be open at once,
  and every launch leaves a small record that helps diagnose a problem.

## [1.0.2] - 2026-11-18

Speed and safety for very large clips.

### Changed

- **Large copies use less memory**: capturing a big image, file or text now peaks at about twice its size, and
  saving it is several times faster.
- **Search stays instant**: indexing reads only what it needs, source names are looked up much faster, and a search
  the system leaves unanswered now ends by itself.
- **Less work in the background**: card dates stop updating while the panel is hidden, and the text recognition
  queue no longer rewrites settings after every image.
- Coming back to the history tab is immediate.

### Fixed

- **Pasting large images no longer stalls**: a very large image is prepared in the background instead of freezing
  Pasto for seconds.

### Security

- **Link previews**: Pasto fetches the page itself, reads only its head, and refuses redirects to local or private
  addresses.

## [1.0.1] - 2026-11-18

Fixes and polish after the first release.

### Added

- **Spanish**: the whole app is available in Spanish.
- **Accessibility**: VoiceOver reads cards, tabs and controls, cards have actions, and Reduce Motion and Increase
  Contrast are respected.
- **Help**: a Help menu with getting started, keyboard shortcuts and *Report a Problem…*, which sends nothing by
  itself.
- **Recovery**: if the database cannot be opened, Pasto offers to set it aside and start fresh instead of quitting.

### Changed

- **Faster with a large history**: the list, captures, searches and clean-ups stay quick with hundreds of thousands
  of clips, and Pasto uses far less memory for large copies.
- **Your shortcuts on a new Mac**: Pasto now sets ⇧⌘V and ⇧⌘C on first launch, or the nearest free alternatives,
  and tells you if another app takes a shortcut later.
- The feature for pasting several clips in a row is now simply called *Stack*.

### Fixed

- **Search no longer quits Pasto**: typing in the search field could close the app.
- Many small fixes to tabs, the toolbar, previews, the Stack and Settings.

### Security

- **Privacy**: Pasto no longer hands the text of your clips to system search, link previews are not fetched from
  local or private addresses, and Pasto's files can only be read by you.

## [1.0.0] - 2026-11-17

The first release of Pasto, a clipboard manager for your Mac. Pasto needs macOS 27 or later.

### Added

- **History**: everything you copy, in a panel that slides up from the bottom of the screen. Press the shortcut,
  pick a card and it is pasted where you were.
- **Pinboards**: keep the clips you reuse in lists of their own.
- **Search**: find any clip by its text, by the app it came from or by the words in an image.
- **Preview and edit**: look at a clip with Space and change it before pasting; write new text items with ⌘N.
- **Stack**: collect several clips and paste them one after another.
- **Suggestions**: Pasto can look at the window you are pasting into and put the clips that fit it first.
- **Updates**: Pasto checks for new versions once a day. You can also choose *Check for Updates…* in its menu.

[Unreleased]: https://github.com/jnjambrin0/Pasto/compare/v1.0.6...HEAD
[1.0.6]: https://github.com/jnjambrin0/Pasto/releases/tag/v1.0.6
[1.0.5]: https://github.com/jnjambrin0/Pasto/releases/tag/v1.0.5
[1.0.4]: https://github.com/jnjambrin0/Pasto/releases/tag/v1.0.4
[1.0.3]: https://github.com/jnjambrin0/Pasto/releases/tag/v1.0.3
[1.0.2]: https://github.com/jnjambrin0/Pasto/releases/tag/v1.0.2
[1.0.1]: https://github.com/jnjambrin0/Pasto/releases/tag/v1.0.1
[1.0.0]: https://github.com/jnjambrin0/Pasto/releases/tag/v1.0.0
