#!/bin/bash
# Runs the repo test suites:
#   • UpdatePolicy unit tests (spec S-0001 §8.6 T-2/T-5)
#   • desktop plugin unit tests (vitest; spec S-0002)
#
# The Swift test compiles app/Sources/UpdatePolicy.swift +
# tests/UpdatePolicyTests.swift into a CLI runner and executes it. The plugin
# tests run through the pnpm workspace (mirrors dsk-poc's vitest layout).
# Exits non-zero on any failure, so CI and local development treat it as a gate.
#
# Usage (from the repo root):
#   ./scripts/run-tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMP_BIN="$(mktemp -d)/UpdatePolicyTests"
trap 'rm -rf "$(dirname "$TMP_BIN")"' EXIT

SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "==> Compiling UpdatePolicy tests…"
swiftc -target arm64-apple-macos13.0 -sdk "$SDK" -o "$TMP_BIN" \
  app/Sources/UpdatePolicy.swift tests/UpdatePolicyTests.swift

echo "==> Running UpdatePolicy tests…"
"$TMP_BIN"

# Plugin tests (vitest). pnpm is a build-time requirement for plugins.
if [ -d "$ROOT/plugins" ]; then
  echo "==> Running plugin tests…"
  (cd "$ROOT" && pnpm -r --filter './plugins/*' test)
fi
