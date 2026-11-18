# SoundKit

Generates Pasto's two feedback sounds, copy and paste, from code: synthesized tones with an
exponential decay, so no audio file has to be hand-made or borrowed. Copy is two soft rising
notes (0.21 s); paste is one short, lower tap (0.08 s).

```bash
swift Tools/SoundKit/generate-sounds.swift              # writes Pasto/Sounds/PastoCopy.aiff and PastoPaste.aiff
swift Tools/SoundKit/generate-sounds.swift /some/folder
```

Run it from the repository root. The files live in `Pasto/Sounds/`, a synchronized folder of the
app target, so they reach the bundle without touching the project; `SoundFeedback` in `PastoApp`
loads them as system sounds. Edit the partials in `generate-sounds.swift` and run it again to
change a sound.
