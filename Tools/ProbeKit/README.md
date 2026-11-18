# ProbeKit

Pasto's UI automation and measurement toolkit. It drives Pasto the way a person would (keys, clicks,
drags, scrolls, clipboard copies) and measures what happens: show and hide timing, window geometry,
layout and colours in screenshots, the accessibility tree, and what reaches the clipboard and the
app you paste into. Use it during development to check a change, to compare two builds, or to
record an animation frame by frame.

No dependencies beyond the SDK: Swift 6, AppKit, ScreenCaptureKit and the Accessibility API.

| Target | What it is |
|---|---|
| `pastoprobe` | The command-line tool: one subcommand per probe. |
| `ProbeTarget` | A minimal AppKit app that logs focus, key events, drops and pastes, used as the paste destination. |
| `ProbeCore` | The shared library: capture, events, image and accessibility diffs, argument parsing. Unit-tested. |

## Requirements and permissions

- macOS 27 and a Swift 6.4 toolchain.
- Permissions belong to the *responsible* process, the terminal (or IDE) that launches the tool, not to
  the binary. Grant them in System Settings > Privacy & Security:
  - **Accessibility**: `ax-dump`, `ax-menu`, and every command that posts input (`key`, `keys`, `hold`,
    `type`, `click`, `drag`, `move`, `scroll`).
  - **Screen & System Audio Recording**: `shot`, `frames` and `pixel --screen`.
- The tool never prompts. A missing permission ends the command with exit code 2 and a message naming
  the pane to open. `pastoprobe perms` shows what the responsible process holds.

## Build, test, run

```bash
cd Tools/ProbeKit
swift build -c release                   # binaries in .build/release/
swift test                               # pure logic: image and AX diffs, scanlines, key combos, arguments
.build/release/pastoprobe help           # or: swift run -c release pastoprobe <subcommand>
.build/release/pastoprobe <subcommand> --help
```

## Choosing the app: `--app`

| Value | Resolves to |
|---|---|
| `pasto` | The development build that `scripts/run.sh` installs (`jnjambrino.Pasto.dev`). |
| `pasto-release` | An installed release (`jnjambrino.Pasto`). |
| a bundle id | Any running app with that identifier. |
| a pid | Any process, including `ProbeTarget`, which has no bundle id. |

The app must be running. Commands that need a single window take `--window <id>` (from `windows`) or
`--app <app> --largest`.

## Output conventions

- Results go to standard output as pretty-printed JSON. Exceptions: `win-poll` and `trace` print CSV;
  `pb-watch`, `file-watch` and `front --watch` print one JSON object per line; `--csv` and `--outline`
  select compact text where offered.
- Diagnostics and errors go to standard error.
- Screen coordinates are points with a top-left origin. Commands that read image files (`pixel --image`,
  `scanline`, `colors`, `trace`, `stack --crop`) take image pixels.
- `--display` and `--screen` take `main` or a zero-based index into the active displays; a `--rect`
  given with `--display` is relative to that display's top-left corner.
- Exit codes: `0` ok, `1` usage, `2` permission missing, `3` target not found, `4` runtime failure.

## `pastoprobe` subcommands

Defaults are shown as option values.

### Windows and accessibility

| Subcommand | What it does | Example |
|---|---|---|
| `windows` | The app's windows as the window server sees them, on screen or not: id, pid, owner, layer, bounds, alpha, `isOnscreen`, name, `sharingState`. `--all` lists every app's windows. | `pastoprobe windows --app pasto` |
| `win-poll` | Samples one window's bounds, alpha and visibility as CSV `t_ms,x,y,w,h,alpha,onscreen` (`--hz 240`, `--duration 2`). `--until-change` starts the clock at the first change; the last unchanged row gets a negative time. `--new-at-layer N` waits for a window that was not there at that layer (1000 for the OSD, 25 for the Paste Stack) and samples it from the moment it exists. Both give up after `--timeout 30`. | `pastoprobe win-poll --app pasto --largest --hz 240 --duration 1 --until-change` |
| `ax-dump` | The accessibility tree with frames (role, subrole, identifier, title, value…). `--window-index N`, `--max-depth 64`, `--max-nodes 20000`, `--no-values`. | `pastoprobe ax-dump --app pasto > before.json` |
| `ax-diff` | Compares two dumps, pairing children by role and index among siblings: frame deltas beyond `--tolerance 0.5`, missing and extra nodes, a summary. For before/after checks or two builds. | `pastoprobe ax-diff before.json after.json` |
| `ax-menu` | The menu the app is showing (context, pop-up or status-item menu): items in order with title, shortcut, mark, state and submenus. `--at x,y` points inside the menu; `--extras` lists the app's status items instead; `--outline` prints one indented line per item; `--max-depth 6`. | `pastoprobe ax-menu --app pasto --at 289,786 --outline` |

### Capture and image analysis

| Subcommand | What it does | Example |
|---|---|---|
| `shot` | A PNG of one window at native scale (`--shadow` includes the shadow) or of a composited display region (`--display main [--rect x,y,w,h]`). Without `--out`, writes to the temporary directory. | `pastoprobe shot --app pasto --largest --out panel.png` · `pastoprobe shot --display main --rect 0,785,1728,332 --out region.png` |
| `frames` | Records a window or display region as PNGs named by millisecond plus `index.csv` (`frame,t_ms`) into `--out <dir>`: `--fps 120` (at most 240), `--duration 2`. Reports frames delivered, unique, written and dropped. | `pastoprobe frames --display main --rect 0,785,1728,332 --fps 120 --duration 2 --out show/` |
| `trace` | Turns a `frames` recording into a CSV time series, one row per frame: point colours (`--points x,y:x,y`, `--size 1`), where an edge sits along a line (`--edge col:x:from:to --bg #RRGGBB`, `--tolerance 8`, `--from-end`), and each region's progress between two reference frames (`--progress x,y,w,h`: k in frame ≈ start + k·(end − start); for a cross-fade, the incoming opacity; `--start first`, `--end last` or a `t_ms`). `--changed-only` skips repeated rows. | `pastoprobe trace show/ --edge col:3:0:682 --bg '#FFFFFF' --changed-only` |
| `imgdiff` | Per-pixel sRGB difference: count, percentage, mean and maximum delta, bounding box. `--threshold 2`; `--out` writes a heat map; `--crop-common` compares the shared top-left region of images of different sizes. | `pastoprobe imgdiff before.png after.png --out diff.png` |
| `pixel` | The sRGB colour of an image pixel (`--image <file>`) or of a screen point (`--screen`), or the mean of an n×n block (`--size n`). | `pastoprobe pixel --image panel.png --at 120,48 --size 3` · `pastoprobe pixel --screen --at 864,900` |
| `scanline` | Runs of near-constant colour along a row or column of one or more images (start, end, length, colour): edges, paddings, corner profiles and stroke widths without looking at the image. `--from`/`--to` limit the line, `--tolerance 0`, `--min-run 1` merges shorter runs, `--against ref.png` reports where the line differs from another image's, `--csv` is the compact output. | `pastoprobe scanline --image panel.png --row 440 --tolerance 2 --min-run 2 --csv` |
| `colors` | Colour census of a rectangle: the `--top 5` most frequent, the brightest and the darkest (the nominal colour of antialiased text or of a fill). `--csv` for one line per colour. | `pastoprobe colors --image panel.png --rect 2184,150,80,40 --csv` |
| `stack` | Stacks images, or the same `--crop` of each, top to bottom into one PNG, to see a frame sequence at a glance. | `pastoprobe stack f/000100.png f/000117.png --crop 0,0,800,120 --out seq.png` |
| `backdrop` | A solid-colour strip (`--color black\|white\|gray\|#RRGGBB`) behind the panel, to capture translucent windows over a known background. Bottom 400 pt by default, `--rect` for another region, `--screen main`, `--level 3`, `--seconds 8`. See [Safety](#safety). | `pastoprobe backdrop --color white --seconds 6 &` |

### Input

| Subcommand | What it does | Example |
|---|---|---|
| `key` | Posts one combo (`cmd+shift+v`, `return`, `escape`, `left`, `cmd+1`…): presses the modifiers, the key, and releases in reverse order. `--hold-ms 20`. | `pastoprobe key cmd+shift+v` |
| `keys` | Several combos from one process, each at an offset from the first key-down (`combo@ms`) or `--gap-ms 100` after the previous one; `--hold-ms 20`. It warms up the event connection first, so its timestamps do not carry the first-event delay. | `pastoprobe keys cmd+shift+v@0 return@60` · `pastoprobe keys right right right --gap-ms 60` |
| `hold` | Holds modifiers alone (`cmd`, `shift`, `opt`, `ctrl`, `fn`, joined with `+`) for `--ms 1500` after `--delay-ms 0`, and reports when they went down and up. For hints shown while ⌘ is held. | `pastoprobe hold cmd --ms 1500` |
| `type` | Types text as Unicode key events, independent of the keyboard layout. `--interval-ms 15`. | `pastoprobe type "hello" --interval-ms 15` |
| `click` | Clicks at a point: `--count 1` (up to 5), `--right`, `--mods cmd+shift` held during the click, `--down-ms 30`. | `pastoprobe click 300,900 --count 2` |
| `drag` | Left-button drag between two points over `--duration-ms 300`. `--hold-ms` keeps the button down at the end; `--start-hold-ms` keeps it down at the start (press a button, then drag off it without triggering it); `--via x,y --via-hold-ms` drags in two legs with a pause at the waypoint (hover a tab, drop elsewhere). | `pastoprobe drag 720,815 400,830 --start-hold-ms 1200` · `pastoprobe drag 372,1000 500,300 --via 928,815 --via-hold-ms 1500` |
| `move` | Moves the pointer without pressing; with `--from x0,y0` it glides there over `--duration-ms 200` so tracking views see it enter. Reports `arrivedContinuousMs`. | `pastoprobe move 1208,985 --from 1208,820 --duration-ms 250` |
| `scroll` | Scroll-wheel events at a point: `--dy`, `--dx` (positive scrolls up / left), line units unless `--pixels`, `--count 1`, `--interval-ms 16`. | `pastoprobe scroll 900,960 --dy -3` |
| `front` | The frontmost app; `--watch [--duration s]` prints a line per app activation and deactivation; `--activate <pid>` asks an app without a bundle id (such as `ProbeTarget`) to activate, which the system may refuse. | `pastoprobe front --watch --duration 10` |

### Clipboard and files

| Subcommand | What it does | Example |
|---|---|---|
| `seed` | Copies a deterministic sequence to the clipboard, one item every `--interval-ms 900`: plain, multi-line and long text, rich text, links, colours, code, emoji and CJK, images, files. `--set basic` (7 items) or `full` (14); `--list` only lists them; `--fixtures <dir>` moves the generated files. | `pastoprobe seed --set full --interval-ms 900` |
| `pb-dump` | The general pasteboard: `changeCount` and, per item, each type with its size; `--content` adds the first 200 characters of textual types; `--allow-prompt` reads data even when that may show the system alert. | `pastoprobe pb-dump --content` |
| `pb-watch` | A line each time the pasteboard's `changeCount` moves, with the types (never reads data). `--hz 20`, `--duration`. | `pastoprobe pb-watch --duration 10` |
| `file-watch` | A line each time a file is written, extended, renamed or deleted; when it disappears, reopens it as soon as it exists again (SQLite `-wal` files). `--duration`. | `pastoprobe file-watch ~/Library/…/db.sqlite-wal --duration 10` |
| `perms` | Accessibility, event posting and listening, screen recording and pasteboard access of the responsible process. | `pastoprobe perms` |

## `ProbeTarget`

A minimal AppKit app with an `NSTextView` (focused at launch), an `NSTextField` and an
`NSSecureTextField` (accessibility identifiers `probe.textView`, `probe.textField`, `probe.secureField`).
It is the destination for paste and drag tests. It writes newline-delimited JSON: app and window
activation, every `keyDown`/`keyUp`/`flagsChanged` (key code, characters, modifiers, the event's own
timestamp, and the source pid and state of the `CGEvent`), every drag that enters the text
(`dragEntered`: operation mask and, per item, types with sizes and the first characters of textual
ones) and every `drop`, every paste (`pasteBegin`: `changeCount` and types with sizes; `pasteEnd`:
inserted length), and text changes (length only, never content).

```bash
.build/release/ProbeTarget --log "$TMPDIR/target.jsonl" --title "Destination" --frame 200,120,640,480 \
    --clear-on-paste --copy-source lazy:1500 &
```

At launch it prints its log path, pid and window id. `--clear-on-paste` empties the text after each
paste. `--fullscreen` makes the window full screen; `--floating` keeps it at the floating level (above a
terminal that covers the screen, so a click can activate it). `--copy-source lazy:<ms>` adds a button and
⌘⇧L that publish a promised string whose provider takes `<ms>` to deliver it, to test how Pasto
captures slow lazy data. Without `--log` it writes to the per-user temporary directory. It quits
cleanly on SIGTERM or SIGINT.

## Clocks

`t_ms` is always `mach_continuous_time` in milliseconds. Event logs (`ProbeTarget`, `pb-watch`,
`file-watch`, `front --watch`, `seed`) use the absolute value since boot, so logs from different
processes line up. `win-poll` and `frames` count from their own origin and publish it so it can be
added back: `t0_continuous_ms=` on standard error for `win-poll`, `t0ContinuousMs` in the `frames`
report. Input commands report when they acted on the same clock (`keyDownContinuousMs`,
`mouseDownContinuousMs`, `downContinuousMs`/`upContinuousMs`, `arrivedContinuousMs`,
`firstEventContinuousMs`), so the difference to a logged change is the latency from input to change.

## Safety

`backdrop` puts an opaque window over part of the screen, so it is built never to get in the way:

- It never covers the full screen: the bottom 400 pt by default or the `--rect` you give, and it refuses
  anything over 60 % of the screen. It does not take the mouse.
- It exits by itself after `--seconds` (8 by default, at most 10), or on SIGINT/SIGTERM.
- In a script, tie it to the script's lifetime with a trap. Afterwards
  `pgrep -f "pastoprobe backdrop"` must print nothing.

Measuring the panel's show animation over a white background (bottom 332 pt of a 1728×1117 display):

```bash
trap 'pkill -f "pastoprobe backdrop"' EXIT
pastoprobe backdrop --color white --seconds 6 & sleep 0.5
pastoprobe frames --display main --rect 0,785,1728,332 --fps 120 --duration 1 --out show/ & sleep 0.4
pastoprobe keys cmd+shift+v; wait %2; pastoprobe keys escape
pkill -f "pastoprobe backdrop"
```

## Known limitations

- `key` stamps `keyDownContinuousMs` before posting, and the first event a process posts takes
  ≈ 55–65 ms to go out. With modifiers the modifier key absorbs it; with a bare key (Esc, Return) the
  measured latency is inflated by that amount. Use `keys` for timing.
- Only one ScreenCaptureKit capture runs at a time: `shot` or `pixel --screen` while `frames` records
  in another process interrupts the recording (it stays partial, `streamError` says why, exit code 4).
- `shot --shadow` uses `/usr/sbin/screencapture` (ScreenCaptureKit shrinks the window to make room for
  the shadow) and is reliable only while the window is visible; without `--shadow`, hidden windows can
  be captured too.
- `ax-menu` needs `--at` when the menu does not hold the app's accessibility focus, which is usual for
  context menus. The menu's window has a 75 pt shadow margin, so the point must fall inside the menu.
- Accessibility frames of text, images and buttons can be up to 1 pt larger per side than what is
  drawn; check them with `scanline` before relying on them.
- `frames` receives "complete" frames even when nothing changed; `uniqueFrames` counts the ones that
  differ from the previous frame.
- `pb-dump` reads data only when pasteboard access is `alwaysAllow`; otherwise it lists types.
- `seed` writes its files to `.fixtures/` (ignored by git).
- `ProbeTarget` is an unbundled executable: it has no bundle id, so address it by pid.
- The responsible process's name comes from a private libSystem symbol resolved at run time; when the
  symbol is missing, `perms` omits it.
