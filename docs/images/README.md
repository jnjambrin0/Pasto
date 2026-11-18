# Screenshots

The images the main [README](../../README.md) shows. Each file name below is referenced from there; to update an
image, replace the file in place, keeping its name, and recapture the same scene so the README's captions and alt
texts stay true.

## How to capture

- **Dark appearance**, English, a plain dark green wallpaper, the menu bar and Dock out of the frame.
- **No personal data.** Run a development build with an empty history and copy sample content into it:
  `scripts/run.sh --in-memory-store` keeps the history in memory, so nothing of yours shows and nothing is left
  behind. Device filters show the Mac's name (*System Settings › General › About › Name*), so give the Mac a
  neutral name before capturing search.
- **Retina, PNG.** Capture at 2× (sizes below are in pixels) and run the files through a lossless optimiser (such as
  `oxipng` or ImageOptim); keep each image under about 1 MB.
- Panel images are cropped to the full width of the screen; window images are window captures (⇧⌘4, then Space,
  then click the window), which keep the shadow.

## The images

| File | Size (px) | Scene |
|---|---|---|
| `panel.png` | 3456 × 784 | **Hero.** The panel alone, on the *Clipboard* tab with a red *Pasto Links* pinboard next to it, showing a row of cards: three texts (a short message, a meeting address, a code snippet), a link with its image, an image, a colour (`#2BA65B`) and the first welcome note. The first card is selected |
| `search.png` | 3456 × 784 | The panel searching: *pasto* typed in the search field, the suggested filters under it and the matching items, from the history and from the pinboard, in the strip below |
| `preview.png` | 3456 × 1314 | The preview open above the second text card (the meeting address), with its *Edit* button and its character, word and line counts, and the panel below |
| `onboarding.png` | 1312 × 1248 | The welcome window's first step: the illustration of cards growing from the grass and *Get Started* |
| `suggestions.png` | 1312 × 1510 | The welcome window's *Smart Suggestions* step, with suggestions on and the screen recording permission not yet granted |
| `stack.png` | 1120 × 1294 | The Stack panel with its first-use hint and three text rows waiting to be pasted |
| `settings.png` | 1504 × 1324 | *Settings › General*: open at login, sound effects, paste items, plain text and the *Keep history* slider |

*Help › Getting Started* shows the welcome window at any time. The README shows `panel.png`, `search.png` and
`preview.png` at full width, and the four window images in a row at 200 pt wide each, so keep each window centred
with little margin around it.
