#!/bin/bash
# One-click installer for dsh-desktop.
# The app is fully self-contained — it bundles Node + the dsh backend, so
# nothing else needs to be installed or started.
#
#   ./install.sh            build + install to /Applications + launch
#   ./install.sh --dmg      install from the pre-built .dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="dsh-desktop"
APP_BUNDLE="$ROOT/dist/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

if [ "${1:-}" = "--dmg" ]; then
    echo "==> Mounting installer DMG…"
    DMG=$(ls "$ROOT"/dist/dsh-desktop-*.dmg 2>/dev/null | head -1)
    [ -n "$DMG" ] || { echo "No .dmg found in $ROOT/dist"; exit 1; }
    MOUNT=$(hdiutil attach "$DMG" -nobrowse | awk '/Volumes\// {print $NF; exit}')
    APP_BUNDLE="$MOUNT/${APP_NAME}.app"
else
    echo "==> Building ${APP_NAME}.app…"
    "$ROOT/build.sh" >/dev/null
fi

echo "==> Installing to /Applications"
if [ -d "$DEST" ]; then
    echo "    Removing previous version"
    rm -rf "$DEST"
fi
ditto "$APP_BUNDLE" "$DEST"

# Fix quarantine on downloaded copies
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching ${APP_NAME}"
open "$DEST"

echo ""
echo "✅ dsh-desktop installed at $DEST"
echo "   It starts its own embedded backend on launch — no external server needed."
