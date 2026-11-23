# Hanko Mix

A free, open-source menu bar app for macOS that controls the volume of each app separately — plus per-device EQ (with AutoEQ headphone presets), balance and mono.

It uses the Core Audio **process taps** API (macOS 14.4+): no audio driver, no kernel extension, no admin password. If Hanko Mix quits or crashes, every app immediately goes back to playing normally.

> Named after Hanko, the author's dog. 🐶 License still to be decided.

## Features

- **Per-app volume and mute** — 0–200 %, with a soft limiter above 100 % so loud apps never distort.
- **Per-app output** — send Spotify to your headphones and Zoom to your speakers.
- **Per-device EQ** — up to 10 parametric bands plus preamp, and a searchable catalog of ~6,000 [AutoEQ](https://github.com/jaakkopasanen/AutoEq) headphone presets.
- **Balance and mono** per output device.
- **Quick device switching** — pick the system output and microphone right from the menu.
- **Microphone gain and mute** from the menu (no microphone permission needed; Hanko Mix never listens to it).
- **Remembers each app's settings** and applies them when it plays again.
- **Hands off by default** — an app you haven't touched is never intercepted, so its sound is bit-identical and adds no latency.

## Requirements

- macOS 14.4 or later (Apple Silicon or Intel)
- Xcode 16 or later (Swift 6) to build

## Build and run

```bash
scripts/build-app.sh
open "build/Hanko Mix.app"
```

The build is ad-hoc signed, not notarized. The first time, macOS may refuse to open it: right-click the app in Finder → **Open**, or allow it in **System Settings → Privacy & Security**.

The first time you change an app's volume, Hanko Mix explains — and macOS then asks for — the **System Audio Recording** permission. It is needed to capture an app's audio, process it and play it back. Audio never leaves your Mac and nothing is written to disk.

## Development

```bash
swift build
swift test
```

Developer tool for testing the audio engine from the terminal:

```bash
swift run pav-diag list
```

```bash
swift run pav-diag watch
```

```bash
swift run pav-diag tap --app com.spotify.client --volume 0.3
```

The AutoEQ index is regenerated with `scripts/generate-autoeq.sh`.

Project layout:

| Path | Contents |
|---|---|
| `Sources/PAVCore` | Pure, tested logic: DSP, the tap planner, process grouping, settings, AutoEQ |
| `Sources/PAVAudio` | Core Audio: system monitor, tap/aggregate backend, reconciling engine |
| `Sources/HankoMix` | The SwiftUI menu bar app |
| `Sources/pav-diag`, `Sources/autoeq-index` | Command-line tools |
| `docs/superpowers/specs`, `docs/superpowers/plans` | Design and implementation plan |
| `docs/manual-test-checklist.md` | What to check by hand before a release |

## Known limitations

- AirPlay and multi-output devices can't be chosen as a per-app output (they add ~2 s of latency as an aggregate's clock). Apps you haven't touched still play to AirPlay normally.
- Processed audio is a stereo mixdown; multichannel devices receive front left/right only.
- If an app plays to several devices at once, only the first one is used.

## Credits

Headphone presets from [AutoEq](https://github.com/jaakkopasanen/AutoEq) by Jaakko Pasanen (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
