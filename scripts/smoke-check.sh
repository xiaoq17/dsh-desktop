#!/bin/bash
# Product-level smoke validation (spec S-0001 §8.6 T-4).
#
# Verifies that the built artifacts are structurally correct — this catches
# "built OK but wrong version/product/manifest" regressions that a plain
# type-check cannot.
#
# Checks:
#   1. dist/<app>.app/Contents/Info.plist key fields
#      (CFBundleShortVersionString / CFBundleVersion / DSHGitRevision /
#       CFBundleIdentifier / CFBundleExecutable)
#   2. Contents/Helpers/dsh-updater exists and is executable
#   3. dist/update-manifest*.json fields (version / build / platform / app /
#      dmgSha256 / dmgUrl)
#   4. dist/<app>-<version>-arm64.dmg exists (non-empty)
#
# Usage (from the repo root):
#   ./scripts/smoke-check.sh [full|light]   # default: full
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VARIANT="${1:-full}"
if [ "$VARIANT" = "light" ]; then
  APP="dist/dsh-desktop-light.app"
  APP_NAME="dsh-desktop-light"
  PLIST="dist/dsh-desktop-light.app/Contents/Info.plist"
  MANIFESTS=("dist/update-manifest-light.json" "dist/dev-update-light.json")
else
  APP="dist/dsh-desktop.app"
  APP_NAME="dsh-desktop"
  PLIST="dist/dsh-desktop.app/Contents/Info.plist"
  MANIFESTS=("dist/update-manifest.json" "dist/dev-update.json")
fi

echo "==> Smoke-checking $VARIANT artifacts ($APP_NAME)…"

[ -f "$PLIST" ] || { echo "✗ $PLIST missing"; exit 1; }

# 1. Info.plist key fields.
for key in CFBundleShortVersionString CFBundleVersion DSHGitRevision \
           CFBundleIdentifier CFBundleExecutable; do
  val="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null || true)"
  [ -n "$val" ] || { echo "✗ $key missing in $PLIST"; exit 1; }
  echo "  ✓ $key = $val"
done

# The short version must be four dot-separated numeric components.
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
case "$VER" in
  [0-9]*.[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "✗ CFBundleShortVersionString not four-part: $VER"; exit 1 ;;
esac

# 2. Helper present and executable.
HELPER="$APP/Contents/Helpers/dsh-updater"
[ -x "$HELPER" ] || { echo "✗ helper missing/not executable: $HELPER"; exit 1; }
echo "  ✓ helper = $HELPER"

# 3. Manifest fields. A release manifest may not exist yet in a fresh checkout
# (dev-update.sh writes it on demand) — only validate manifests that exist.
for m in "${MANIFESTS[@]}"; do
  [ -f "$m" ] || { echo "  - (no manifest $m — skipping)"; continue; }
  for key in version build app platform dmgSha256 dmgUrl; do
    val="$(python3 -c "import json,sys; print(json.load(open('$m')).get('$key',''))" 2>/dev/null || true)"
    [ -n "$val" ] || { echo "✗ manifest $m missing field $key"; exit 1; }
  done
  echo "  ✓ manifest $m fields complete"
done

# 4. DMG exists (non-empty).
DMG="$(ls dist/${APP_NAME}-*-arm64.dmg 2>/dev/null | head -1 || true)"
[ -n "$DMG" ] && [ -s "$DMG" ] || { echo "✗ no non-empty DMG for $APP_NAME"; exit 1; }
echo "  ✓ dmg = $DMG ($(du -h "$DMG" | cut -f1))"

echo "==> Smoke-check OK ($VARIANT)"
