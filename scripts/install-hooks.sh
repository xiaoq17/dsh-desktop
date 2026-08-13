#!/bin/bash
# Installs the Spec-First pre-commit hook into this repo's .git/hooks/.
#
# The ByteDance bytesec hook is configured via the GLOBAL core.hooksPath and
# already chains to .git/hooks/pre-commit, so both run — nothing is
# overwritten or disabled. Run this after cloning (or if .git was recreated).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/scripts/hooks/pre-commit"
DEST="$REPO/.git/hooks/pre-commit"

mkdir -p "$REPO/.git/hooks"
cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "✅ Installed spec-first hook: $DEST"
echo "   (runs after the bytesec security scan, which chains local .git/hooks/pre-commit)"
