# Quick Output Switching and Microphone Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the menu bar popover, switch the system output and input devices, change the microphone gain, and mute/unmute the microphone.

**Architecture:** Pure models and the mute strategy go in `PAVCore`. Reading and writing device properties go in `PAVAudio`: `AudioSystemMonitor` reads, and a new `AudioDeviceControl` writes. `AppState` adds intents and the popover gets an Output picker and a Microphone section. No audio streams are opened.

**Tech Stack:** Swift 6.3, Core Audio HAL properties, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-23-quick-output-and-mic-design.md`

## Global Constraints

- Language: all code, comments, docs, commit messages and UI strings are in English.
- Never open an input stream or require the microphone permission for this feature.
- PerAppVolume's own aggregates (UID prefix `io.github.perappvolume.`) never appear in any picker.
- Mute fallback restores the remembered volume, or `0.5` when none is remembered.
- Commits: conventional messages, no `Co-Authored-By` or AI attribution trailer.

## Review Focus

1. **Microphone with neither volume nor mute** (common on Bluetooth headsets): the slider and mute button are disabled, nothing is written, and nothing crashes. → Task 1 `unsupportedDeviceDoesNothing`.
2. **Mute via volume, then the app restarts** while the volume is 0: unmuting restores 50 % instead of staying at 0. → Task 1 `volumeOnlyUnmuteWithoutMemoryRestoresHalf`.
3. **Default input or output changed from System Settings:** the popover follows. → Task 2 listeners, manual check.
4. **Per-channel-only input volume** (no main element): both channels are set and the average is read back. → Task 2 `averageOfChannelVolumes`.
5. **AirPlay as system output:** it is offered in the Output picker even though it is excluded from per-app outputs. → Task 1 `airPlayIsSelectableAsSystemOutput`.

---

### Task 1: Input device model, mute strategy, system output filter

**Files:**
- Create: `Sources/PAVCore/Model/InputDevice.swift`, `Sources/PAVCore/Planning/MicMuteStrategy.swift`
- Modify: `Sources/PAVCore/Model/SystemSnapshot.swift` (add `inputDevices: [InputDevice] = []` and `defaultInputUID: String? = nil` to the stored properties and to `init`, with defaults)
- Modify: `Sources/PAVAudio/DeviceFilter.swift`
- Test: `Tests/PAVCoreTests/MicMuteStrategyTests.swift`, `Tests/PAVAudioTests/DeviceFilterTests.swift`

**Interfaces:**
- Produces:
  - `public struct InputDevice: Sendable, Hashable { uid: String; name: String; transport: TransportKind; volume: Float?; volumeSettable: Bool; muted: Bool?; muteSettable: Bool }`
  - `public enum MicAction: Sendable, Equatable { case setMute(Bool), setVolume(Float), unsupported }`
  - `public enum MicMuteStrategy`, with:
    - `static func isMuted(_ d: InputDevice) -> Bool`: `muted == true`, or (`!muteSettable && volumeSettable && volume == 0`).
    - `static func toggle(_ d: InputDevice, rememberedVolume: Float?) -> (action: MicAction, remember: Float?)`
  - `DeviceFilter.isSelectableAsSystemOutput(_ d: OutputDevice) -> Bool`: true unless the UID has our prefix.

- [ ] **Step 1: Write the failing tests.**
  - `deviceMuteIsUsedWhenAvailable`: `muteSettable`, `muted false` → `.setMute(true)`, and `remember` is unchanged.
  - `deviceMuteUnmutes`: `muted true` → `.setMute(false)`.
  - `volumeOnlyMuteRemembersVolume`: volume `0.7`, not muted → `(.setVolume(0), 0.7)`.
  - `volumeOnlyUnmuteRestoresRememberedVolume`: volume `0`, remembered `0.7` → `(.setVolume(0.7), nil)`.
  - `volumeOnlyUnmuteWithoutMemoryRestoresHalf`: volume `0`, `nil` → `.setVolume(0.5)`.
  - `unsupportedDeviceDoesNothing`: neither settable → `.unsupported`.
  - `airPlayIsSelectableAsSystemOutput` and `ownAggregateIsNotSelectableAsSystemOutput`.
- [ ] **Step 2: `swift test`.** Expected: FAIL (the types don't exist).
- [ ] **Step 3: Implement** the Interfaces.
- [ ] **Step 4: `swift test`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: input device model, mic mute strategy and system output filter`.

### Task 2: Read and write device properties

**Files:**
- Modify: `Sources/PAVAudio/AudioSystemMonitor.swift`, which fills `inputDevices`/`defaultInputUID` and listens to them.
- Create: `Sources/PAVAudio/AudioDeviceControl.swift`
- Modify: `Sources/pav-diag/main.swift`, so `list` also prints the inputs.
- Test: `Tests/PAVAudioTests/AudioDeviceControlTests.swift`

**Interfaces:**
- Consumes: `InputDevice`, `SystemSnapshot` (Task 1).
- Produces:
  - `public enum AudioDeviceControl`, with:
    - `static func setDefaultOutput(uid:) throws`
    - `static func setDefaultInput(uid:) throws`
    - `static func setInputVolume(uid:, _ v: Float) throws`
    - `static func setInputMute(uid:, _ m: Bool) throws`
    - `static func averageOfChannelVolumes(_ values: [Float]) -> Float?`: a pure function, `nil` for an empty array.
  - UID → `AudioObjectID` resolution uses `kAudioHardwarePropertyTranslateUIDToDevice`.

**Details:**
- Input devices are those with input streams and no own prefix.
- Volume: `kAudioDevicePropertyVolumeScalar`, scope input.
  - If the main element is settable (`AudioObjectIsPropertySettable`), use it.
  - Otherwise use elements `1...channels` (input stream configuration) and read back their average.
- Mute: `kAudioDevicePropertyMute`, scope input, main element.
- Defaults: `kAudioHardwarePropertyDefaultOutputDevice` / `DefaultInputDevice` on the system object.
- New listeners:
  - On the system object: the default input.
  - On each input device: volume and mute on the input scope, for the main element and channels 1–2.

- [ ] **Step 1: Write the failing test** `averageOfChannelVolumes`: `[0.4, 0.6]` → `0.5`, and `[]` → `nil`.
- [ ] **Step 2: `swift test --filter AudioDeviceControlTests`.** Expected: FAIL.
- [ ] **Step 3: Implement** `AudioDeviceControl` and the monitor changes, and add the inputs to `pav-diag list`.
- [ ] **Step 4: `swift test`.** Expected: PASS. Then `swift run pav-diag list` prints an `Inputs:` section with the MacBook mic, the Poly mic, their volume and mute, and `*` on the default input.
- [ ] **Step 5: Commit** `feat: read and control system output/input devices and mic gain/mute`.

### Task 3: Popover UI and intents

**Files:**
- Modify: `Sources/PerAppVolume/AppState.swift`, `Sources/PerAppVolume/Views/MenuBarView.swift`, `Sources/PerAppVolume/Views/DeviceSectionView.swift`
- Create: `Sources/PerAppVolume/Views/MicrophoneSectionView.swift`
- Modify: `docs/manual-test-checklist.md`, `README.md` (features list)

**Interfaces:**
- Consumes: `AudioDeviceControl`, `MicMuteStrategy`, `DeviceFilter.isSelectableAsSystemOutput`.
- Produces on `AppState`:
  - `systemOutputDevices: [OutputDevice]`, `inputDevices: [InputDevice]`, `defaultInput: InputDevice?`
  - `setSystemOutput(_ uid: String)`
  - `setSystemInput(_ uid: String)`
  - `setMicVolume(_ v: Float)`
  - `toggleMicMute()`
  - `deviceError: String?`, shown under the sections when a write fails

**Behaviour:**
- Writes run on the audio queue, never on the main thread. The next snapshot refreshes the UI.
- The remembered pre-mute volume is kept in memory per input UID.
- Volume and mute are disabled when the device doesn't support them, with the tooltip from the spec.

- [ ] **Step 1: Implement** the intents and views: the Output picker in place of the device label, and the Microphone section with picker, slider, percentage and mute button.
- [ ] **Step 2: `swift build` without warnings; `swift test`.** Expected: PASS.
- [ ] **Step 3: Update** the checklist and the README.
  - Checklist additions: switch the output from the menu; switch the mic; gain; mute and unmute; a mic without volume control; a change from System Settings is reflected.
- [ ] **Step 4: `scripts/build-app.sh`, relaunch.** Manual check: switching Poly ↔ MacBook speakers moves the sound, and the mic gain moves the Input level in System Settings → Sound.
- [ ] **Step 5: Commit** `feat: quick output switching and microphone controls in the menu`.
