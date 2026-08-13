#!/bin/bash
# Local-development update helper.
#
# Rebuilds dsh-desktop, packages a DMG and writes a file:// update manifest so
# the RUNNING app can pick up the fresh build through the SAME flow as a GitHub
# release: background staging -> "Restart to Install…" reminder -> user clicks.
#
# Usage (from the repo root):
#   ./scripts/dev-update.sh                       # stage a local update for the
#                                                # FULL dsh-desktop (writes
#                                                # dist/dev-update.json)
#   DSH_LIGHT=1 ./scripts/dev-update.sh           # stage a local update for the
#                                                # LIGHT dsh-desktop-light
#                                                # (writes dist/dev-update-light.json)
#                                                # — full & light upgrade
#                                                # independently (spec S-0001 §8.3)
# The desktop rev is derived from the most recent release tag (0 if none) and
# the manifest "build" is the git short rev, so ANY different rev is detected as
# a new build (no desktop-rev bump needed).
# The script then AUTO-WRITES the DSHUpdateManifestURL override for the running
# bundle (file:// to this manifest), so no manual `defaults write` is needed.
# After the local update is applied, the app clears the file:// override and
# reverts to the default GitHub URL (spec S-0001 FR-9.11).
#
# Then in the app menu: dsh-desktop -> Check for Updates… (or wait for the
# silent check). The update is staged + verified, the "Restart to Install…"
# menu item lights up and the Dock icon bounces once; click it to apply.
#
# NOTE: each run rebuilds + repackages, which takes a while; the updater swaps
# via the DMG (same as production).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
./scripts/build.sh

echo "==> Packaging DMG…"
./scripts/make-dmg.sh

APP="dist/${APP_NAME}.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP")"
DMG="$ROOT/dist/${APP_NAME}-${VERSION}-arm64.dmg"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

# JSON-escape a string for embedding in a manifest (RFC 8259, spec S-0001 §8.3).
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
}

cat > "dist/$MANIFEST" <<EOF
{
  "version": $(json_escape "$VERSION"),
  "build": $(json_escape "$BUILD"),
  "app": $(json_escape "$APP_NAME"),
  "minOSVersion": "13.0",
  "arch": "arm64",
  "platform": "darwin",
  "dmgUrl": $(json_escape "file://$DMG"),
  "dmgSha256": $(json_escape "$SHA"),
  "releaseNotes": $(json_escape "• Local development build $VERSION ($APP_NAME)")
}
EOF

echo
echo "✅ Local update staged:"
echo "   manifest : $ROOT/dist/$MANIFEST"
echo "   dmg      : $DMG ($VERSION, build $BUILD)"

echo
echo "==> Pointing the running $APP_NAME at the local manifest…"
defaults write "$BUNDLE_ID" DSHUpdateManifestURL "file://$ROOT/dist/$MANIFEST"
echo "    DSHUpdateManifestURL = file://$ROOT/dist/$MANIFEST"

echo
echo "Open/Check for Updates… in $APP_NAME to apply; the override is cleared"
echo "automatically after the update is installed (spec S-0001 FR-9.11)."
