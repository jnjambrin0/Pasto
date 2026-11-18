# StressKit

`pastostress` checks that Pasto's store and item list hold up after a year of heavy use. It
generates a deterministic store of hundreds of thousands of items (70 % short text, 15 % long
text, 10 % images, 5 % links, files and colours, a year of timestamps, 2 000 items on pinboards)
with `PastoCore`'s own store code, then measures it: opening and migrating the store, browsing
the item list, shrinking the history capacity and erasing the history. Each scenario runs in a
process of its own on an APFS clone of the store and reports wall time, main-thread CPU, memory
and disk use.

## Run

Build and run it optimised; debug numbers are meaningless.

```bash
cd Tools/StressKit
swift run -c release pastostress help
swift run -c release pastostress run --count 300000 --work /tmp/pastostress --json /tmp/after.json --label after
swift run -c release pastostress generate --count 100000 --dir /tmp/store-100k
swift run -c release pastostress measure --dir /tmp/store-100k
swift run -c release pastostress scenario browse --store /tmp/store-100k
```

`run` reuses the store in `<work>/store-<count>` when there is one (`--regenerate` makes a new
one). A large store takes a while to generate and needs room on disk; `--image-scale` makes the
images smaller or larger (at 1, each weighs 0.2–5 MB). Compare two `--json` reports to see what a
change costs.
