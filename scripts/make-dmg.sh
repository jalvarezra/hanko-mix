#!/usr/bin/env bash
# Builds build/HankoMix-<version>.dmg: "Hanko Mix.app" plus an Applications shortcut.
#
# Signing (optional):
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"  sign app + DMG with Developer ID
#   NOTARY_PROFILE="hanko-notary"                                 also notarize + staple
#     (create the profile once with: xcrun notarytool store-credentials hanko-notary)
# Without DEVELOPER_ID the app keeps its ad-hoc signature; see README for first-launch steps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build-app.sh"

APP="$ROOT/build/Hanko Mix.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' App/Info.plist)"
DMG="$ROOT/build/HankoMix-$VERSION.dmg"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "Signing with Developer ID: $DEVELOPER_ID"
  codesign --force --options runtime --timestamp --entitlements App/HankoMix.entitlements \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --deep --strict "$APP"
else
  echo "No DEVELOPER_ID set: keeping the ad-hoc signature (users must allow the app on first launch)."
fi

STAGING="$(mktemp -d "$ROOT/build/dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Hanko Mix" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 -quiet "$DMG"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

hdiutil verify -quiet "$DMG"
echo "Built $DMG"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
