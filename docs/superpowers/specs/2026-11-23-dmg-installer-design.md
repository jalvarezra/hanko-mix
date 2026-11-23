# DMG installer — Design

*Date: 2026-11-23 · Status: approved by the user · Size: small change*

## Intent

Ship Hanko Mix as a standard macOS disk image that people download, open, and drag into Applications.

## Approaches

| Approach | Verdict |
|---|---|
| **`.dmg` with the app and an Applications shortcut** (drag to install), built with the system's `hdiutil` | **Chosen.** It's the usual way to ship a menu bar app, and it needs no extra tools. |
| `.pkg` installer | Rejected. It's only needed when installing outside the app bundle (drivers, daemons), and Hanko Mix installs nothing there. |

## Design

- `scripts/make-dmg.sh` runs `scripts/build-app.sh` and writes `build/HankoMix-<version>.dmg`. The version comes from `CFBundleShortVersionString` in `App/Info.plist`. The volume is named "Hanko Mix" and contains `Hanko Mix.app` plus an `Applications` symlink. The image is compressed (UDZO). The script prints the path and SHA-256 of the DMG.
- **Signing has two automatic modes:**
  - **Default (no Apple Developer account):** ad-hoc signature, as now. The first time on another Mac, macOS blocks the app. The user allows it in System Settings → Privacy & Security → **Open Anyway**. The README explains this.
  - **With `DEVELOPER_ID`** (a "Developer ID Application: …" identity in the keychain): sign the app with hardened runtime and a secure timestamp, then sign the DMG. If `NOTARY_PROFILE` is also set (a `notarytool` keychain profile), notarize and staple, so it opens with no warning.
- The user's Apple Developer enrollment was declined, so the default mode is the one that ships for now.

## Non-goals (later)

- A custom DMG window background or icon layout.
- Publishing on GitHub Releases or Homebrew. That comes when the repo is on GitHub.
