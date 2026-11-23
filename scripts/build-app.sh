#!/usr/bin/env bash
# Builds build/PerAppVolume.app (universal, ad-hoc signed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --arch arm64 --arch x86_64 --product PerAppVolume
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="$ROOT/build/PerAppVolume.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp App/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/PerAppVolume" "$APP/Contents/MacOS/PerAppVolume"
# SwiftPM resource bundle (autoeq.json); Bundle.module finds it in Contents/Resources.
cp -R "$BIN_DIR/PerAppVolume_PerAppVolume.bundle" "$APP/Contents/Resources/"

codesign --force --options runtime --entitlements App/PerAppVolume.entitlements -s - "$APP"
echo "Built $APP"
