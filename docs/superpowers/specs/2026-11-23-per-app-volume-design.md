# Per-app volume for macOS — Design (v1)

*Date: 2026-11-23 · Status: draft for approval*
*Project name: to be decided (the code provisionally uses `PerAppVolume`).*

## 1. Intent and why

A **free and open-source** alternative to commercial per-app volume apps for macOS: a menu bar app that controls the audio of each application separately. In this version, "improved" means open, with no paid license or artificial limitations, and reliable.

The feature the user uses most is **adjusting volume per app**. That is the piece that has to work perfectly. The rest of the v1 features are built around it.

## 3. Goals (v1)

1. **Per-app volume and mute** *(the core)*.
   - One slider for each app that is playing or has played in this session, from 0 % to 200 %.
   - Above 100 % a soft limiter is applied to avoid digital clipping.
   - Per-app mute button.
2. **Per-app output**: send an app to an output device other than the default.
3. **Per-output-device EQ**.
   - Parametric EQ per device, with an AutoEQ preset search by headphone model.
   - Can be turned on and off.
4. **Balance and mono** per output device.
5. **Remember per-app settings**.
   - Volume, mute and output are saved per *bundle ID* and applied automatically when the app plays again.
   - EQ, balance and mono settings are saved per device *UID*.
6. **Open source** from the first commit: public repo, build instructions and license.

## 4. Non-goals (for after v1)

- Per-app EQ.
- Global keyboard shortcuts and MIDI control.
- Apple Music control, AppleScript or URL scheme.
- Processing the microphone or audio input.
- Recording, effects or third-party AU plugins.
- Support for macOS earlier than 14.4.
- **AirPlay and multi-output devices as per-app output** (user's decision). They do not appear in the per-app output menu.
  - Reason: as the main device of an aggregate they add about 2 s of latency and their clock is not reliable.
  - If the system default output is AirPlay, untouched apps play normally, because they are not intercepted. Those with their own settings keep working in "best effort" mode, and the user is warned that there may be delay.
- Distribution through the Mac App Store.

## 5. Anti-goals (it would fail even if it "works")

- **Altering audio at rest.** If the user has not touched anything, the sound must be bit-identical with no added latency. An app at 100 % volume, not muted, on its default output and with no EQ, balance or mono active on that device **is not intercepted**.
- **Leaving the user without sound.**
  - If the app quits or crashes, everything must go back to sounding normal. Private taps and aggregates die with the process.
  - If creating a tap or an aggregate fails, that app keeps playing unprocessed and a discreet warning is shown. It is never left silent.
- Audible **dropouts, clicks or desync** when moving a slider, when connecting or disconnecting headphones, or when changing the default output.
- **Installing drivers, kexts or asking for an administrator password.**
- **Copying code or resources from other apps.**

## 6. Constraints

- macOS **14.4 or later**. `CATapDescription` exists since 14.2, but the audio capture permission (`NSAudioCaptureUsageDescription`) settles in 14.4. *My decision*: raising the minimum to 14.4 avoids a separate permissions path. If testing requires it, the builder can raise it to 14.6. It must be tested on 14.x, 15.x and 26.x.
- Apple Silicon and also Intel (universal binary). There are no dependencies that prevent it.
- **System audio capture permission**: requires `NSAudioCaptureUsageDescription`. The first time a tap is created, macOS asks the user for permission. The app must explain beforehand why it needs it and handle the permission-denied case.
- **Sandbox**: An app using process taps can run sandboxed with `com.apple.security.device.audio-input`. v1 can ship with or without sandbox; *builder's decision*, preferably sandboxed if it causes no problems.
- **Signing and notarization**: without an Apple Developer account, the app opens with a Gatekeeper warning. *Pending user decision* (see §11); it does not change the code.

## 7. Approaches considered

| Approach | What it involves | Verdict |
|---|---|---|
| **A. Native Swift app, single process** | SwiftUI `MenuBarExtra`. The same app creates the taps and aggregates and processes the audio in the Core Audio callback. | **Chosen by the user.** It is the simplest and cannot leave you without sound: when the process dies, macOS destroys the private taps. |
| B. App + background agent (XPC) | The interface and the audio engine run in separate processes. | Discarded for v1: twice the pieces for an advantage (restarting the UI without cutting audio) that is not needed yet. It can be split later. |
| C. Virtual HAL driver | Like Background Music or eqMac. | Discarded: requires installing a driver with administrator privileges, tends to break with macOS updates and clashes with the anti-goals. |

## 8. Design (what was decided)

### 8.1 Pieces

- **`AudioSystem`**: observes Core Audio.
  - Output devices, default output and list of audio processes (`kAudioHardwarePropertyProcessObjectList`).
  - For each process it reads PID, *bundle ID* and whether it is playing (`kAudioProcessPropertyIsRunningOutput`).
  - Publishes changes through listeners, never by polling.
- **`AppGrouper`**: groups processes into "apps" as the user sees them.
  - Helper processes (for example "Google Chrome Helper (Renderer)", WebKit/Safari, Electron) are assigned to their main app via the responsible process or the bundle hierarchy.
  - The UI shows one row per app, not per process.
- **`TapEngine`**: creates and destroys private taps and aggregate devices, and manages the audio callbacks.
- **`DSP`**: real-time processing chain.
  - Ramped gain (no clicks), soft limiter for more than 100 %, parametric EQ with biquads (vDSP) and balance/mono matrix.
  - The callback code does not allocate memory or take locks. Parameters are passed with atomic or *lock-free* structures.
- **`SettingsStore`**: persistence.
  - JSON in `~/Library/Application Support/<app>/`.
  - Per *bundle ID*: volume, mute and output UID. Per device UID: EQ, balance and mono.
- **`AutoEQCatalog`**: index of AutoEQ parametric presets, searchable by model.
- **UI**: SwiftUI `MenuBarExtra` plus a settings window.

### 8.2 When an app is intercepted (core rule)

An app **needs processing** if it meets any of these conditions:

- volume ≠ 100 %
- it is muted
- it has an assigned output different from the default output
- its effective output device has EQ, balance or mono active

If it does not need processing, no tap is created for it.

*Revised after the final review (2026-11-23):* only an app's **own** settings (volume, mute, routing) give it a tap of its own. Device EQ, balance or mono alone is applied by the device's "rest" tap (§8.3), not by per-app taps.
- A tap for an app with its own settings **stays alive while the app's process exists, playing or paused**. Releasing it on pause made a lowered or muted app play at full volume for ~100–300 ms on every resume, before a new tap could be built. The cost is one idle aggregate per adjusted app.
- A new tap starts directly at its target gain; it never fades from 100 %.

**Seamless transitions** *(my decision)*.
- A tap is **created** the first time an app needs processing. That single moment may produce a brief dropout.
- The tap is **not destroyed** when returning to default values. It is kept alive, in transparent mode (gain 1.0, no DSP), until the app stops playing. Only then is it released. (This keep-alive applies to apps back at their defaults; apps that still have their own settings keep their tap as described above.)
- That way, moving a slider 100 % → 99 % → 100 % never recreates anything.
- The "don't taint" test (§9) is defined as: *an app that has not been touched since it started playing has no tap*.

**Helper processes that appear and disappear** (Chrome, Electron).
- The tap is not recreated. Its process list is updated live by writing `kAudioTapPropertyDescription`.
- The aggregate device does not change.

**Effective output device of an app** *(my decision)*.
- If the user has not assigned an output, the tap goes out through the **device the app is actually using**, read from the process properties in Core Audio. If an app like Zoom chose some USB headphones in its own settings, changing its volume does not divert it to the default output.
- In the per-app output menu, the default option is called "Automatic (whatever the app uses)".
- If a process uses several devices at once, the first one is taken and the case is recorded as a known limitation.

### 8.3 Tap topology

**Apps with their own settings** (volume, mute or output): one tap per app.
- `CATapDescription` with the process objects of that app, private and with `muteBehavior = mutedWhenTapped`.
- That tap goes into a private aggregate device whose *main/clock device* is the app's effective output device, with drift compensation enabled.
- The aggregate's IOProc reads the audio from the tap, applies gain and then the device chain (EQ, balance, mono), and writes to the output.

**Devices with EQ, balance or mono active**: additionally, one "rest" tap per device.
- Exclusive tap (`exclusive = true`) **bound to that device**, with `CATapDescription(excludingProcesses:andDeviceUID:withStream:)`. It captures *all apps playing through it except* those that already have their own tap and PerAppVolume's own process. It is only created if that device is the default output, or if some app goes to it.
- It passes through the device chain and goes out through it.

**Rebuilding**: taps and aggregates are recreated only when their composition changes (processes or device). Moving a slider only changes DSP parameters and never recreates anything.

**Cleanup at launch**: aggregates and taps with the app's UID prefix left over from a previous run (for example, after a crash) are removed.

### 8.4 System events

- **An app starts or stops playing**: it appears in or disappears from the list, and its saved settings are applied.
- **An app quits**: its tap is destroyed and its settings are kept.
- **The default output changes**: the affected aggregates are recreated towards the new device.
- **An assigned device is disconnected** (for example, Bluetooth headphones): the assigned apps temporarily move to the default output. When the device comes back, they return to it. The saved assignment is not lost.
- **The device sample rate changes**: the aggregate is recreated and the EQ coefficients are recalculated.

### 8.4b Latency *(my decision)*

- **Target**: at most ~20 ms of added latency on built-in, USB or wired outputs while an app is processed. With that, video and video calls do not drift out of sync noticeably.
- Use small I/O buffers and a lightweight DSP chain inside the callback.
- On Bluetooth the latency is already large because of the device itself. The goal is not to add more than those ~20 ms.
- If an implementation with AudioUnits does not meet the target, custom biquads with vDSP are used.

### 8.5 Interface (sketch)

```
┌─────────────────────────────────────┐
│ 🔊 Output: AirPods Pro         ▾    │
│ ─────────────────────────────────── │
│ [Spotify]   ━━━━━━━━●━━━  80%  🔇 ▾ │
│ [Chrome]    ━━━━━━━━━━━●  100% 🔇 ▾ │
│ [Zoom]      ━━━━━━━━━━━━━●140% 🔇 ▾ │  ▾ = choose that app's output
│ ─────────────────────────────────── │
│ AirPods Pro: EQ AutoEQ ✓  Bal ◦  Mono ☐ │
│ Settings…                     Quit  │
└─────────────────────────────────────┘
```

- The list shows the apps that are playing at the top and, dimmed, those that played recently.
- Double-clicking a slider returns it to 100 %.
- **Settings window**:
  - a tab per device: parametric EQ with AutoEQ search, balance and mono
  - list of remembered apps, with an option to forget them
  - launch at login, with `SMAppService`
  - explanation of the audio permission

### 8.6 AutoEQ

- Parametric presets are generated **at build time** from the AutoEQ repo (jaakkopasanen/AutoEq) as a compact JSON bundled in the app.
- Nothing is downloaded at runtime.
- The license and source are cited in the credits. *Verify the exact license of the data before bundling it.*
- Plan B if the data cannot be bundled *(my decision)*: v1 ships without the AutoEQ search, only with manual parametric EQ, and adds import of an AutoEQ `ParametricEQ.txt` file that the user downloads themselves. Nothing is downloaded automatically.

## 9. Testing

- **Unit tests**:
  - DSP: ramped gain, limiter, EQ frequency response and balance/mono matrix, checked against expected values.
  - Rule from §8.2.
  - Process grouping.
  - Persistence.
- **"Don't taint" test**: with everything at rest, check that no tap or aggregate of the app exists.
- **Manual checklist** on macOS 14 / 15 / 26, on Apple Silicon and on Intel if possible:
  - Spotify, Music, Chrome, Safari, Zoom/Meet, a game and Electron (Slack/Discord)
  - connect and disconnect Bluetooth and USB headphones
  - change the default output
  - kill the app with `kill -9` and check that audio goes back to normal

## 10. Left to the builder's discretion

- Xcode project / Swift Package structure and module organization.
- Whether to use sandbox (see §6).
- Concrete DSP implementation: custom biquads with vDSP or Apple AudioUnits, as long as "no clicks" and "no memory allocations in the callback" are met.
- Number of manual EQ bands (proposal: up to 10 parametric bands, which is enough for AutoEQ).
- Exact format of the settings JSON, with a version field for migrations.
- CI pipeline (GitHub Actions: build and tests).

## 11. Pending from the user (does not block the design)

- Project **name**.
- **License**: proposal **MIT**, for simplicity and so that anyone can reuse it. GPL-3.0 if improvements should be required to stay open.
- **Signing and notarization**: Apple Developer account (99 USD per year) or distribute without notarization via GitHub Releases + Homebrew cask.
