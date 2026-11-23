# Quick output switching and microphone controls — Design

*Date: 2026-11-23 · Status: approved by the user · Size: small change on top of v1*

## Intent

From the menu bar popover, without opening Settings, the user wants to:

1. **Switch the system output device** (where everything plays by default).
2. **Pick the system microphone** (the default input that Zoom, Meet and the rest use).
3. **Change the microphone's gain** and **mute/unmute it quickly**.

## Approaches

| Approach | Verdict |
|---|---|
| **Use the devices' own controls through Core Audio**: default output/input device properties, the input volume scalar and mute properties. | **Chosen.** Needs no microphone permission, never reads the user's voice, and the orange mic indicator never lights up. |
| Virtual microphone (a driver that apps record from, with PerAppVolume processing the real mic) | Rejected. Only needed to *process* the voice (EQ, noise reduction), which is out of scope. It needs a driver, which v1's anti-goals rule out. |

## Design

**Output** (replaces the device header in the menu):
- The output device name becomes a **picker** listing every output device (AirPlay included; PerAppVolume's own private aggregates excluded). Choosing one sets the **system default output**.
- EQ and Mono toggles below it keep working on the selected device.
- Apps on "Automatic" follow the new default; apps with an assigned output stay where they are (existing v1 behaviour).

**Microphone** (new section under Output):
- **Picker** of input devices; choosing one sets the **system default input**.
- **Gain slider 0–100 %** using the device's input volume. Use the main element when it is settable; otherwise set every input channel element to the same value, and read back their average. If the device has no settable input volume, the slider is disabled with the tooltip "This microphone doesn't support volume control".
- **Mute button.** Use the device's input mute property when settable. Otherwise mute by setting the volume to 0 and remember the previous volume in memory; unmuting restores it (or 50 % if none is remembered, e.g. after a restart). If the device supports neither, the button is disabled.
- Everything stays in sync with System Settings: listeners on the default input/output and on each input device's volume and mute.
- No microphone permission is needed, and PerAppVolume never opens an input stream for this feature.

**Known consequence (documented, not fixed):** choosing a Bluetooth headset's mic (e.g. the Poly VSurround 80) makes macOS switch the headset to hands-free mode while an app records, which lowers playback quality. That is a Bluetooth limitation.

## Non-goals

- Live input level meter (it would open the mic and light the orange indicator).
- Keyboard shortcut to mute the mic (comes with the global shortcuts feature).
- Processing the microphone (EQ, noise reduction).

## Left to the builder

- Exact layout and symbols of the popover sections.
- Whether the remembered pre-mute volume lives only in memory (default) or is persisted.
