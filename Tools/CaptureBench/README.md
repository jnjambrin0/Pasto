# CaptureBench

Measures what heavy content costs Pasto: capturing and restoring large items, decoding card
thumbnails, searching a large index, polling the pasteboard at rest and fetching link previews.
It drives the real `PastoCore` pipeline (`SystemPasteboard`, `HistoryManager`, the on-disk store)
over a pasteboard of its own.

A run never touches the general pasteboard, Pasto's store, its settings or its search index: it
works in its own directory (`$TMPDIR/capturebench` by default, `--dir` to change it), its own
settings suite and its own Spotlight index. Every measuring command runs in a process of its own,
so the peak memory it reports is its own.

## Run

Build in release; debug numbers are meaningless.

```bash
cd Tools/CaptureBench
swift run -c release capturebench --help
swift run -c release capturebench suite                       # capture every kind and size, then restore
swift run -c release capturebench capture --kind image --mb 50
swift run -c release capturebench thumbnails --count 5000
swift run -c release capturebench search-fill --docs 100000 && swift run -c release capturebench search-query --docs 100000
swift run -c release capturebench search-clean                # delete the benchmark's index
swift run -c release capturebench idle --seconds 60           # CPU and wakeups at rest
swift run -c release capturebench link-compare                # needs the network
```

`--help` lists every command and option. `Support/Info.plist` is embedded in the executable to
give it a bundle identifier, which Core Spotlight needs to keep an index for it.
