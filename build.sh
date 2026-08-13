#!/bin/bash
# Builds dsh-desktop (.app bundle) from the Swift sources.
# The app is fully self-contained: it bundles its own Node runtime and the
# @deepseek-ai/dsh package (with production dependencies) under Resources/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# Variant: DSH_LIGHT=1 builds dsh-desktop-light — no bundled Node/dsh; at
# runtime it reuses the INSTALLED full dsh-desktop.app's runtime
# (spec S-0001 §8.5).
LIGHT="${DSH_LIGHT:-0}"
if [ "$LIGHT" = "1" ]; then
  APP_NAME="dsh-desktop-light"
  EXEC_NAME="DSHDesktopLight"
  BUNDLE_ID="com.deepseek.dsh.desktop.light"
else
  APP_NAME="dsh-desktop"
  EXEC_NAME="DSHDesktop"
  BUNDLE_ID="com.deepseek.dsh.desktop"
fi

# ── Version scheme ──────────────────────────────────────────────────
# Desktop version is FOUR parts:  <dsh major>.<dsh minor>.<dsh patch>.<rev>
#   • the first three parts ALWAYS mirror the embedded @deepseek-ai/dsh
#     version (read from its package.json at build time, prerelease dropped)
#   • the fourth part is the desktop revision, starting at 0 and
#     incremented for desktop-only fixes; it resets when dsh is upgraded.
# Override the revision per build:
#   DSH_DESKTOP_REV=3 ./build.sh
# Default DSH_DESKTOP_REV: traced back from git history — the desktop revision
# of the MOST RECENT release tag (v<dsh>.<dsh>.<dsh>.<rev>), so a build made
# after a release keeps that release's revision until a new one is cut; no
# release tag yet → 0.
# CFBundleVersion (the update "build" number) carries the build source's git
# short revision, so an update is detected whenever the rev differs.
if [ -z "${DSH_DESKTOP_REV:-}" ]; then
  LAST_RELEASE_TAG="$(git -C "$ROOT" tag --sort=-version:refname 2>/dev/null | grep -E '^v[0-9]' | head -1 || true)"
  if [ -n "$LAST_RELEASE_TAG" ]; then
    DSH_DESKTOP_REV="${LAST_RELEASE_TAG##*.}"
  else
    DSH_DESKTOP_REV=0
  fi
fi

# Where the auto-update manifest is hosted — the app polls this URL.
# Default: the GitHub Releases "latest" asset of this repo. Override at build:
#   DSH_UPDATE_MANIFEST_URL="https://…/update-manifest.json" ./build.sh
# At runtime it can also be overridden per-machine:
#   defaults write com.deepseek.dsh.desktop DSHUpdateManifestURL "https://…"
# Light variant uses its own manifest asset (spec S-0001 §7.4).
DEFAULT_MANIFEST_ASSET="update-manifest.json"
if [ "$LIGHT" = "1" ]; then DEFAULT_MANIFEST_ASSET="update-manifest-light.json"; fi
DSH_UPDATE_MANIFEST_URL="${DSH_UPDATE_MANIFEST_URL:-https://github.com/xiaoq17/dsh-desktop/releases/latest/download/${DEFAULT_MANIFEST_ASSET}}"

# Git revision embedded for the title bar's "(rev:…)" — the short commit hash
# of the code being built. Falls back to the desktop revision outside a git
# checkout (e.g. a release tarball).
if GIT_REV="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null)"; then
  DSH_GIT_REV="$GIT_REV"
else
  DSH_GIT_REV="$DSH_DESKTOP_REV"
fi

BUILD_DIR="$ROOT/build"
APP_BUNDLE="$ROOT/dist/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
RUNTIME="$RESOURCES/runtime"
DSH_EMBED="$RESOURCES/dsh"

NODE_VERSION="v22.16.0"
NODE_TARBALL="$BUILD_DIR/node-${NODE_VERSION}-darwin-arm64.tar.gz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-darwin-arm64.tar.gz"

echo "==> Cleaning old build"
rm -rf "$BUILD_DIR/DSHDesktop" "$APP_BUNDLE"
mkdir -p "$BUILD_DIR" "$MACOS" "$RESOURCES"

# ── 1. Bundle the Node runtime (full build only) ───────────────────────
if [ "$LIGHT" != "1" ] && [ ! -x "$BUILD_DIR/node-${NODE_VERSION}-darwin-arm64/bin/node" ]; then
  echo "==> Downloading official Node ${NODE_VERSION} (arm64)"
  curl -sL -o "$NODE_TARBALL" "$NODE_URL"
  tar xzf "$NODE_TARBALL" -C "$BUILD_DIR"
fi

# ── 2. Bundle @deepseek-ai/dsh + production deps (full build only) ────
DSH_PKG_VERSION="0.1.0-rc.6"
if [ "$LIGHT" != "1" ] && [ ! -d "$BUILD_DIR/dsh/node_modules/@deepseek-ai/dsh" ]; then
  echo "==> Installing @deepseek-ai/dsh (production deps only)"
  mkdir -p "$BUILD_DIR/dsh"
  (cd "$BUILD_DIR/dsh" \
    && npm install --omit=dev --no-audit --no-fund "@deepseek-ai/dsh@${DSH_PKG_VERSION}" >/dev/null)
fi

# ── 2b. Derive the desktop version from the dsh version ────────────────
# First three parts mirror dsh's; fourth is the desktop revision (from 0).
# Full build: read the embedded dsh. Light build: read the SYSTEM dsh CLI
# (spec S-0001 §8.5) — resolve via DSH_DSH / `command -v dsh`, fall back to the
# repo's build/dsh.
if [ "$LIGHT" = "1" ]; then
  DSH_PKG_JSON=""
  DSH_BIN="${DSH_DSH:-$(command -v dsh 2>/dev/null || true)}"
  if [ -n "$DSH_BIN" ] && [ -x "$DSH_BIN" ]; then
    DSH_REAL="$(cd "$(dirname "$DSH_BIN")" && python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$DSH_BIN" 2>/dev/null || true)"
    [ -n "$DSH_REAL" ] && DSH_PKG_JSON="$(dirname "$DSH_REAL")/../package.json"
  fi
  [ -f "$DSH_PKG_JSON" ] || DSH_PKG_JSON="$BUILD_DIR/dsh/node_modules/@deepseek-ai/dsh/package.json"
  [ -f "$DSH_PKG_JSON" ] || { echo "Light build needs a system dsh CLI (npm i -g @deepseek-ai/dsh) or DSH_DSH=/path/to/dsh." >&2; exit 1; }
else
  DSH_PKG_JSON="$BUILD_DIR/dsh/node_modules/@deepseek-ai/dsh/package.json"
fi
DSH_VERSION="$(grep -m1 '"version"' "$DSH_PKG_JSON" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
DSH_TRIPLE="$(printf '%s' "$DSH_VERSION" | sed -E 's/-.*$//' | awk -F. '{print $1"."$2"."$3}')"
VERSION="${DSH_TRIPLE}.${DSH_DESKTOP_REV}"
BUILD="${DSH_GIT_REV}"
echo "==> dsh version: $DSH_VERSION → desktop version: $VERSION (rev $DSH_DESKTOP_REV) [$APP_NAME]"

# ── 3. Compile Swift sources ──────────────────────────────────────────
echo "==> Compiling Swift sources (arm64, macOS 13+)"
swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -o "$BUILD_DIR/DSHDesktop" \
  "$ROOT/src/AppDelegate.swift" \
  "$ROOT/src/MainWindowController.swift" \
  "$ROOT/src/EditingWebView.swift" \
  "$ROOT/src/ServerManager.swift" \
  "$ROOT/src/UpdateManager.swift" \
  "$ROOT/src/Platform.swift" \
  -framework Cocoa -framework WebKit

# ── 3b. Compile the standalone updater helper ─────────────────────────
# Standalone Foundation-only executable that swaps the app bundle after the
# main app quits (mirrors Sparkle/Doubao relaunch_helper).
echo "==> Compiling updater helper"
swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -o "$BUILD_DIR/dsh-updater" \
  "$ROOT/src/UpdaterHelper.swift"

# ── 4. Assemble the .app bundle ───────────────────────────────────────
echo "==> Assembling .app bundle"
cp "$BUILD_DIR/DSHDesktop" "$MACOS/$EXEC_NAME"
cp "$ROOT/src/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"

# Updater helper (used by auto-update)
mkdir -p "$CONTENTS/Helpers"
cp "$BUILD_DIR/dsh-updater" "$CONTENTS/Helpers/dsh-updater"
chmod +x "$CONTENTS/Helpers/dsh-updater"

# Embedded runtime: node binary only (npm/npx not needed by the app).
# Skipped for the light variant — it reuses the installed full app (spec §8.5).
if [ "$LIGHT" != "1" ]; then
  mkdir -p "$RUNTIME/bin"
  cp "$BUILD_DIR/node-${NODE_VERSION}-darwin-arm64/bin/node" "$RUNTIME/bin/node"
  chmod +x "$RUNTIME/bin/node"

  # Embedded dsh package tree
  mkdir -p "$DSH_EMBED"
  cp -R "$BUILD_DIR/dsh/node_modules" "$DSH_EMBED/node_modules"
  rm -rf "$DSH_EMBED/node_modules/.bin" 2>/dev/null || true
fi

# Desktop profile template — seeded into $DSH_HOME/profiles/desktop on first launch
cp -R "$ROOT/assets/desktop-profile" "$RESOURCES/desktop-profile"

# Version plist merge
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$CONTENTS/Info.plist" 2>/dev/null || true

# Variant identity (bundle id / display name / executable)
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXEC_NAME" "$CONTENTS/Info.plist" 2>/dev/null || true

# Git revision for the title bar's "(rev:…)"
/usr/libexec/PlistBuddy -c "Set :DSHGitRevision $DSH_GIT_REV" "$CONTENTS/Info.plist" 2>/dev/null || true

# Auto-update manifest URL — only embedded when a real URL is configured.
if [ -n "$DSH_UPDATE_MANIFEST_URL" ]; then
  /usr/libexec/PlistBuddy -c "Delete :DSHUpdateManifestURL" "$CONTENTS/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :DSHUpdateManifestURL string $DSH_UPDATE_MANIFEST_URL" "$CONTENTS/Info.plist"
fi

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Done"
echo "App:   $APP_BUNDLE"
echo "Size:  $(du -sh "$APP_BUNDLE" | cut -f1)"
