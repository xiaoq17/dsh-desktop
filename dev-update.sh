#!/bin/bash
# Local-development update helper.
#
# Rebuilds dsh-desktop, packages a DMG and writes a file:// update manifest so
# the RUNNING app can pick up the fresh build through the SAME flow as a GitHub
# release: background staging -> "Restart to Install…" reminder -> user clicks.
#
# Usage (from the repo root):
#   ./dev-update.sh                              # stage a local update for the
#                                                # FULL dsh-desktop (writes
#                                                # dist/dev-update.json)
#   DSH_LIGHT=1 ./dev-update.sh                  # stage a local update for the
#                                                # LIGHT dsh-desktop-light
#                                                # (writes dist/dev-update-light.json)
#                                                # — full & light upgrade
#                                                # independently (spec S-0001 §8.3)
# The desktop rev is derived from the most recent release tag (0 if none) and
# the manifest "build" is the git short rev, so ANY different rev is detected as
# a new build (no desktop-rev bump needed).
#   defaults write com.deepseek.dsh.desktop DSHUpdateManifestURL \
#     "file://$(pwd)/dist/dev-update.json"       # point the full app at the local manifest
#   defaults write com.deepseek.dsh.desktop.light DSHUpdateManifestURL \
#     "file://$(pwd)/dist/dev-update-light.json" # point the light app at its manifest
#
# Then in the app menu: dsh-desktop -> Check for Updates… (or wait for the
# silent check). The update is staged + verified, the "Restart to Install…"
# menu item lights up and the Dock icon bounces once; click it to apply.
#
# NOTE: each run rebuilds + repackages, which takes a while; the updater swaps
# via the DMG (same as production).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Variant: full (default) or light (DSH_LIGHT=1).
LIGHT="${DSH_LIGHT:-0}"
if [ "$LIGHT" = "1" ]; then
  APP_NAME="dsh-desktop-light"
  BUNDLE_ID="com.deepseek.dsh.desktop.light"
  MANIFEST="dev-update-light.json"
else
  APP_NAME="dsh-desktop"
  BUNDLE_ID="com.deepseek.dsh.desktop"
  MANIFEST="dev-update.json"
fi

echo "==> Building…"
./build.sh

echo "==> Packaging DMG…"
./make-dmg.sh

APP="dist/${APP_NAME}.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP")"
DMG="$ROOT/dist/${APP_NAME}-${VERSION}-arm64.dmg"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

cat > "dist/$MANIFEST" <<EOF
{
  "version": "$VERSION",
  "build": "$BUILD",
  "app": "$APP_NAME",
  "minOSVersion": "13.0",
  "arch": "arm64",
  "platform": "darwin",
  "dmgUrl": "file://$DMG",
  "dmgSha256": "$SHA",
  "releaseNotes": "• Local development build $VERSION ($APP_NAME)"
}
EOF

echo
echo "✅ Local update staged:"
echo "   manifest : $ROOT/dist/$MANIFEST"
echo "   dmg      : $DMG ($VERSION, build $BUILD)"
echo
echo "Point the running $APP_NAME at it, then Check for Updates…:"
echo "   defaults write $BUNDLE_ID DSHUpdateManifestURL \"file://$ROOT/dist/$MANIFEST\""
