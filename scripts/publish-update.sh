#!/bin/bash
# Publishes dsh-desktop update(s) to GitHub Releases:
#   builds the .app(s), packages the .dmg(s), computes SHA-256, writes the
#   update manifest(s), and (optionally) creates the GitHub release + uploads.
#
# The full app is hard-wired to poll:
#   https://github.com/<repo>/releases/latest/download/update-manifest.json
# and the light variant polls:
#   .../update-manifest-light.json
# so a release MUST attach a file literally named `update-manifest.json` (and
# `update-manifest-light.json` for light) plus the versioned .dmg(s). A `--both`
# release attaches both DMGs and both manifests to the SAME tag (full and light
# share the version, spec S-0001 §7.4/§8.3).
#
# Usage:
#   ./scripts/publish-update.sh            # full: build + manifest (dry-run)
#   DSH_LIGHT=1 ./scripts/publish-update.sh # light: build + manifest (dry-run)
#   ./scripts/publish-update.sh --both     # both variants, one release (dry-run)
#   ./scripts/publish-update.sh --release  # also create the GitHub release + upload
#   ./scripts/publish-update.sh --release --both
#   DSH_RELEASE_NOTES="…" ./scripts/publish-update.sh --release
#
# Upload requires either the `gh` CLI (authed) or a GITHUB_TOKEN.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITHUB_REPO="${DSH_GITHUB_REPO:-xiaoq17/dsh-desktop}"
RELEASE_NOTES="${DSH_RELEASE_NOTES:-• Auto-update support.}"
# Platform token written into the manifest (Node-style: darwin / win32 / linux).
DSH_PLATFORM="${DSH_PLATFORM:-darwin}"

# JSON-escape a string for embedding in a manifest (RFC 8259), so values
# containing newlines / quotes / backslashes never produce invalid JSON
# (e.g. multi-line DSH_RELEASE_NOTES, spec S-0001 §8.3).
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
}

DO_RELEASE=0; DO_BOTH=0
for a in "$@"; do
  case "$a" in
    --release) DO_RELEASE=1 ;;
    --both) DO_BOTH=1 ;;
  esac
done
if [ "$DO_BOTH" = "1" ]; then MODE="both"
elif [ "${DSH_LIGHT:-0}" = "1" ]; then MODE="light"
else MODE="full"; fi

DMGS=()        # assets to upload (release mode)
MANIFESTS=()
RELEASE_VERSION=""

# Build one variant (full or light), package its DMG, write its manifest.
# Sets $RELEASE_VERSION (same for both variants — same dsh + same git rev).
build_and_manifest() {
  local LIGHT_FLAG="$1" APP_NAME MANIFEST_NAME
  if [ "$LIGHT_FLAG" = "1" ]; then
    APP_NAME="dsh-desktop-light"; MANIFEST_NAME="update-manifest-light.json"
  else
    APP_NAME="dsh-desktop"; MANIFEST_NAME="update-manifest.json"
  fi

  echo "==> Building $APP_NAME"
  (cd "$ROOT" && DSH_LIGHT="$LIGHT_FLAG" ./scripts/build.sh)

  echo "==> Packaging DMG ($APP_NAME)"
  (cd "$ROOT" && APP_NAME="$APP_NAME" ./scripts/make-dmg.sh)

  local APP_INFO="$ROOT/dist/${APP_NAME}.app/Contents/Info.plist"
  local VERSION BUILD DMG DMG_URL SHA MANIFEST
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO")"
  BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_INFO")"
  DMG="$ROOT/dist/${APP_NAME}-${VERSION}-arm64.dmg"
  [ -f "$DMG" ] || { echo "DMG missing: $DMG"; exit 1; }
  SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
  DMG_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${APP_NAME}-${VERSION}-arm64.dmg"
  MANIFEST="$ROOT/dist/$MANIFEST_NAME"

  cat > "$MANIFEST" <<EOF
{
  "version": $(json_escape "$VERSION"),
  "build": $(json_escape "$BUILD"),
  "app": $(json_escape "$APP_NAME"),
  "minOSVersion": "13.0",
  "arch": "arm64",
  "platform": $(json_escape "$DSH_PLATFORM"),
  "dmgUrl": $(json_escape "$DMG_URL"),
  "dmgSha256": $(json_escape "$SHA"),
  "releaseNotes": $(json_escape "$RELEASE_NOTES")
}
EOF

  echo ""
  echo "==> Built $APP_NAME"
  echo "  DMG:       $DMG ($(du -h "$DMG" | cut -f1))"
  echo "  SHA-256:   $SHA"
  echo "  Manifest:  $MANIFEST"
  echo "  DMG URL:   $DMG_URL"

  [ -n "$RELEASE_VERSION" ] || RELEASE_VERSION="$VERSION"
  DMGS+=("$DMG")
  MANIFESTS+=("$MANIFEST")
}

case "$MODE" in
  both) build_and_manifest 0; build_and_manifest 1 ;;
  light) build_and_manifest 1 ;;
  *) build_and_manifest 0 ;;
esac

TAG="v${RELEASE_VERSION}"

if [ "$DO_RELEASE" = "1" ]; then
    echo ""
    echo "==> Creating GitHub release $TAG on $GITHUB_REPO"
    if command -v gh >/dev/null 2>&1; then
        gh release create "$TAG" \
            "${DMGS[@]}" \
            "${MANIFESTS[@]}" \
            --repo "$GITHUB_REPO" \
            --title "dsh-desktop $RELEASE_VERSION" \
            --notes "$RELEASE_NOTES"
        echo "==> Release created: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
        # Fallback: upload via the REST API with a token (DMGs first so the
        # manifests can reference the final asset URLs).
        curl -fsS -X POST \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/releases" \
            -d "{\"tag_name\":\"${TAG}\",\"name\":\"dsh-desktop ${RELEASE_VERSION}\",\"body\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$RELEASE_NOTES")}" \
            -o /tmp/dsh-release.json
        RELEASE_ID="$(python3 -c 'import json;print(json.load(open("/tmp/dsh-release.json"))["id"])')"
        for asset in "${DMGS[@]}" "${MANIFESTS[@]}"; do
            curl -fsS -X POST \
                -H "Authorization: Bearer $GITHUB_TOKEN" \
                -H "Content-Type: application/octet-stream" \
                "https://uploads.github.com/repos/${GITHUB_REPO}/releases/${RELEASE_ID}/assets?name=$(basename "$asset")" \
                --data-binary "@$asset" -o /dev/null
        done
        echo "==> Release created via REST API: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
    else
        echo ""
        echo "!! --release requested but no upload path available."
        echo "   Install gh (brew install gh) + gh auth login, or export GITHUB_TOKEN."
        echo "   Manual steps:"
        echo "     gh release create $TAG ${DMGS[*]} ${MANIFESTS[*]} --repo $GITHUB_REPO --title \"dsh-desktop $RELEASE_VERSION\""
        exit 1
    fi
else
    echo ""
    echo "==> Dry-run done. To actually publish:"
    echo "     ./scripts/publish-update.sh --release [$([ "$DO_BOTH" = "1" ] && echo "--both")]"
fi
