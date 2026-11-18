# CardGallery

Renders Pasto's item cards to PNG files off screen, using the app's own cell views from
`PastoCoreUI`. Use it to review a card change at every density and appearance without launching
the app, and to diff renders before and after a change (for example with
`pastoprobe imgdiff`, see `Tools/ProbeKit`).

The samples are fixed: the items `pastoprobe seed --set full` puts on the clipboard (texts, rich
text, links, colours, code, emoji and CJK, images, files) plus states the seed cannot produce (a
link whose metadata has not arrived, a dark colour, an unknown item, a pinned item). Images are
drawn at run time, so the tool carries no bitmaps and its output is deterministic.

## Run

```bash
cd Tools/CardGallery
swift run CardGallery --help
swift run CardGallery --out /tmp/cards                                  # dark, every density
swift run CardGallery --out /tmp/cards --appearance light --size-class regular --selected
swift run CardGallery --out /tmp/cards --modifiers cmd                  # shortcut indicators
```

It writes `<out>/<size class>/<sample>.png` at 2x. No window is shown and the app never becomes
active.
