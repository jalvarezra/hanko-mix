# Manual test checklist

Run before each release on macOS 14, 15 and 26 — Apple Silicon, and Intel if possible. Build with `scripts/build-app.sh`.

## Hands off (the main anti-goal)

- [ ] Launch the app and touch nothing while Spotify and Chrome play: the sound is unchanged. `swift run pav-diag list` lists no `uid=io.github.perappvolume.*` device. (Private aggregates are invisible to other processes, so also check the sound itself.)
- [ ] Before granting the permission, moving a slider shows the in-popover explanation; "Not now" leaves every app untouched.

## Per-app volume

- [ ] Lower Spotify to 40 %: the permission explanation appears, then the macOS prompt, then the volume drops with no click or gap after the first one.
- [ ] Drag the slider quickly between 0 % and 200 %: no clicks, no harsh distortion at 200 %.
- [ ] Click the percentage label (or drag near 100 %): it returns to exactly 100 % with no gap.
- [ ] Mute and unmute: smooth fade, no click.
- [ ] Quit and reopen the app; when Spotify plays again it is back at 40 %.
- [ ] Each app: Spotify, Music, Chrome (YouTube), Safari, Zoom or Meet, a game, Slack or Discord. Chrome and Electron apps show as **one** row.
- [ ] Video and calls stay in lip-sync while processed (added latency ≈ 20 ms or less on built-in, wired and USB outputs).

- [ ] Ramp down from 200 % to 100 % and to muted on full-scale music: no harsh clipping at any point.
- [ ] Pause and resume Spotify at 20 % (and a muted Chrome tab): no full-volume burst on resume.

## Permission

- [ ] Deny the "System Audio Recording" prompt: no app goes silent, and the menu shows "Permission denied" with "Open Privacy Settings".
- [ ] Revoke the permission in Privacy settings while apps are processed: they play normally again.

## Per-app output

- [ ] Send Spotify to another device: it plays there and not on the default.
- [ ] Zoom set to a USB headset in Zoom's own settings: changing only its volume keeps it on the headset.
- [ ] Disconnect the assigned Bluetooth headphones while playing: the app moves to the default output. Reconnect them: it moves back.
- [ ] AirPlay and aggregate devices don't appear in the per-app output menu.
- [ ] Assign an app to a USB or Bluetooth **headset with a microphone**: you hear the app, not your own mic; the orange mic indicator does not appear; Bluetooth stays in high-quality (not "hands-free") mode.
- [ ] Same headset as the system default with device EQ on: the same three checks.

## Device EQ, balance, mono

- [ ] Search "HD 650" (or your headphones) in Settings → Devices, apply: the sound changes in every app on that device. Toggle the EQ off: it goes back.
- [ ] Balance fully left: only the left channel plays. Mono: both channels carry the same audio.
- [ ] With the EQ on, change the device's sample rate in Audio MIDI Setup: audio keeps playing correctly.
- [ ] With AirPlay as the system default output, apps you haven't touched play normally.

## Robustness

- [ ] `kill -9` the app while it processes audio: every app immediately plays normally again.
- [ ] Switch the default output while apps are processed: they follow without staying silent.
- [ ] Corrupt `~/Library/Application Support/PerAppVolume/settings.json` (write `{nope`): the app starts with defaults and keeps a `settings.corrupt-*.json` backup.

## Settings

- [ ] Apps tab lists remembered apps; "Forget" removes one.
- [ ] "Open at login" adds the app under System Settings → General → Login Items.
- [ ] "Open Privacy Settings" opens the audio-capture privacy pane.
