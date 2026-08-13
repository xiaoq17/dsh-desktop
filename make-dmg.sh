#!/bin/bash
# Packages dsh-desktop.app into a one-click install .dmg
# (drag the app onto the Applications shortcut).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# Pick which app to package: APP_NAME env override, else the NEWEST built .app
# in dist/ (full dsh-desktop vs dsh-desktop-light, spec S-0001 §8.2/§8.5).
APP_NAME="${APP_NAME:-}"
if [ -z "$APP_NAME" ]; then
  FULL_INFO="$ROOT/dist/dsh-desktop.app/Contents/Info.plist"
  LIGHT_INFO="$ROOT/dist/dsh-desktop-light.app/Contents/Info.plist"
  if [ -f "$LIGHT_INFO" ] && { [ ! -f "$FULL_INFO" ] || [ "$LIGHT_INFO" -nt "$FULL_INFO" ]; }; then
    APP_NAME="dsh-desktop-light"
  else
    APP_NAME="dsh-desktop"
  fi
fi
APP_INFO="$ROOT/dist/${APP_NAME}.app/Contents/Info.plist"
STAGING="$ROOT/build/dmg-staging"

# Derive the DMG name from the built app's version so builds and updates stay
# in lockstep.
[ -f "$APP_INFO" ] || { echo "No built $APP_NAME app found — run ./build.sh first."; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO")"
DMG_NAME="${APP_NAME}-${VERSION}-arm64"

echo "==> Preparing staging dir"
rm -rf "$STAGING"
mkdir -p "$STAGING"

cp -R "$ROOT/dist/${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating .dmg"
rm -f "$ROOT/dist/${DMG_NAME}.dmg"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$ROOT/dist/${DMG_NAME}.dmg"

rm -rf "$STAGING"

echo "==> Done"
echo "DMG: $ROOT/dist/${DMG_NAME}.dmg ($(du -h "$ROOT/dist/${DMG_NAME}.dmg" | cut -f1))"
